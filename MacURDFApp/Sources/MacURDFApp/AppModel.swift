import AppKit
import Combine
import Foundation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers
import simd
import URDFCore

@MainActor
final class AppModel: ObservableObject {
    @Published var openedURL: URL?
    @Published var document: URDFDocument?
    @Published var jointState: JointState = JointState()
    @Published var meshAudits: [MeshAudit] = []
    @Published var packageHints: [URL] = []
    @Published var selectedJointName: String?
    @Published var selectedLinkName: String?
    @Published var statusMessage: String = "Open a .urdf file to begin."
    @Published var displayedIssues: [URDFIssue] = []
    @Published var showVisual: Bool = true
    @Published var showCollision: Bool = false
    /// Bumped only when scene *structure* must rebuild (open/reload/toggles/selection/mesh).
    @Published private(set) var sceneEpoch: Int = 0

    private let loader = URDFLoader()
    private let meshResolver = LocalMeshResolver()
    private let fk = ForwardKinematics()
    private let meshLoader = MeshLoader()

    /// Cached mesh node templates by resolved file URL (clone on use).
    private var meshNodeCache: [URL: SCNNode] = [:]
    /// Security-scoped URLs currently held open (sandbox).
    private var securityScopedURLs: [URL] = []

    var linkTransforms: [String: simd_float4x4] {
        guard let doc = document else { return [:] }
        return fk.transforms(document: doc, state: jointState)
    }

    func openURDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.urdf, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a URDF file (grant folder access so meshes/DAE can load)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url, securityScoped: true)
    }

    func noteOpenedDocument(url: URL?) {
        guard let url else { return }
        load(url: url, securityScoped: true)
    }

    func load(url: URL, securityScoped: Bool = true) {
        releaseSecurityScopedAccess()
        if securityScoped {
            beginSecurityScopedAccess(forDocument: url)
        } else {
            // DnD / programmatic — still attempt scoped access (no-op if not scoped).
            beginSecurityScopedAccess(forDocument: url)
        }

        openedURL = url
        mergePackageHint(fromDocumentURL: url)
        // Re-access hints after merge
        for hint in packageHints {
            retainSecurityScopedIfNeeded(hint)
        }

        meshNodeCache.removeAll()

        do {
            let raw = try loader.load(urdfURL: url)
            let (audited, audits) = raw.applyingMeshAudit(
                resolver: meshResolver,
                packageHints: packageHints
            )
            apply(document: audited, audits: audits)
        } catch {
            document = nil
            meshAudits = []
            jointState = JointState()
            displayedIssues = [
                URDFIssue(
                    severity: .error,
                    file: url.lastPathComponent,
                    message: "Failed to load URDF: \(error.localizedDescription)",
                    hint: "Check XML well-formedness and path"
                ),
            ]
            statusMessage = "Load failed — \(url.lastPathComponent)"
            rebuildSceneStructure()
        }
    }

    func loadFromFolder(_ folderURL: URL) {
        retainSecurityScopedIfNeeded(folderURL)
        addPackageHint(folderURL)
        let urdfs = urdfFiles(in: folderURL)
        if urdfs.isEmpty {
            displayedIssues = [
                URDFIssue(
                    severity: .error,
                    file: folderURL.lastPathComponent,
                    message: "폴더에 .urdf 파일이 없습니다",
                    hint: "URDF가 있는 폴더를 드롭하세요"
                ),
            ]
            statusMessage = "No .urdf in folder"
            return
        }
        if urdfs.count > 1 {
            load(url: urdfs[0], securityScoped: true)
            let warn = URDFIssue(
                severity: .warning,
                file: folderURL.lastPathComponent,
                message: "폴더에 .urdf가 \(urdfs.count)개 있어 첫 파일만 로드했습니다: \(urdfs[0].lastPathComponent)",
                hint: "원하는 파일이면 File > Open으로 직접 선택하세요"
            )
            displayedIssues = [warn] + displayedIssues
            return
        }
        load(url: urdfs[0], securityScoped: true)
    }

    func reload() {
        guard let url = openedURL else {
            statusMessage = "Reload — no file open"
            return
        }
        load(url: url, securityScoped: true)
    }

    func setJoint(_ name: String, value: Double) {
        guard let doc = document else { return }
        var next = jointState
        next.values[name] = value
        next.clamp(to: doc)
        jointState = next
        // Do NOT rebuild scene structure — viewport updates link simdTransform in place.
    }

    func selectJoint(_ name: String?) {
        selectedJointName = name
        if let name, let doc = document,
           let joint = doc.joints.first(where: { $0.name == name }) {
            selectedLinkName = joint.child
        }
        rebuildSceneStructure()
    }

    func selectLink(_ name: String?) {
        selectedLinkName = name
        rebuildSceneStructure()
    }

    func toggleVisual() {
        showVisual.toggle()
        rebuildSceneStructure()
    }

    func toggleCollision() {
        showCollision.toggle()
        rebuildSceneStructure()
    }

    func setShowVisual(_ value: Bool) {
        showVisual = value
        rebuildSceneStructure()
    }

    func setShowCollision(_ value: Bool) {
        showCollision = value
        rebuildSceneStructure()
    }

    /// Returns a clone of the cached mesh node for a resolved URL (STL/OBJ via MeshLoader, DAE via SCNScene).
    /// Blender COLLADA often fails in SceneKit — on DAE failure, tries `visual/X.dae` → `collision/X.stl`.
    func nodeForResolvedMesh(url: URL) -> SCNNode? {
        if let cached = meshNodeCache[url] {
            return cached.clone()
        }
        let ext = url.pathExtension.lowercased()
        if ext == "dae" {
            if let node = loadDAENode(url: url) {
                meshNodeCache[url] = node
                return node.clone()
            }
            // SceneKit/MDL cannot open many Blender DAEs — fall back to collision STL.
            if let stlURL = collisionSTLSibling(ofVisualDAE: url) {
                retainSecurityScopedIfNeeded(stlURL)
                retainSecurityScopedIfNeeded(stlURL.deletingLastPathComponent())
                if let stlNode = loadSTLOrOBJNode(url: stlURL) {
                    let linkHint = stlURL.deletingPathExtension().lastPathComponent
                    appendIssue(
                        severity: .warning,
                        file: url.lastPathComponent,
                        message: "SceneKit이 DAE를 열 수 없어 collision STL로 표시 (\(linkHint))",
                        hint: "DAE: \(url.lastPathComponent) → STL: \(stlURL.path)"
                    )
                    // Cache under DAE key so visual path stops showing yellow placeholders.
                    meshNodeCache[url] = stlNode
                    meshNodeCache[stlURL] = stlNode
                    return stlNode.clone()
                }
                appendIssue(
                    severity: .warning,
                    file: url.lastPathComponent,
                    message: "DAE 실패 → STL 폴백 실패 (\(url.deletingPathExtension().lastPathComponent))",
                    hint: "시도한 STL: \(stlURL.path)"
                )
            } else {
                appendIssue(
                    severity: .warning,
                    file: url.lastPathComponent,
                    message: "DAE 로드 실패 (collision STL 없음): \(url.lastPathComponent)",
                    hint: "visual/*.dae 옆 collision/*.stl 경로를 확인하세요"
                )
            }
            return nil
        }
        return loadSTLOrOBJNode(url: url)?.clone()
    }

    func geometryForResolvedMesh(url: URL) -> SCNGeometry? {
        nodeForResolvedMesh(url: url)?.geometry
    }

    private func loadSTLOrOBJNode(url: URL) -> SCNNode? {
        if let cached = meshNodeCache[url] {
            return cached
        }
        do {
            let buffer = try meshLoader.load(url: url)
            let geo = MeshBufferSceneKit.geometry(from: buffer)
            geo.firstMaterial?.diffuse.contents = NSColor.systemTeal
            let node = SCNNode(geometry: geo)
            meshNodeCache[url] = node
            return node
        } catch {
            appendIssue(
                severity: .warning,
                file: url.lastPathComponent,
                message: "메시 로드 실패: \(url.lastPathComponent)",
                hint: nsErrorDetail(error)
            )
            return nil
        }
    }

    /// `.../visual/linkN.dae` → `.../collision/linkN.stl` (also same-folder `linkN.stl`).
    private func collisionSTLSibling(ofVisualDAE daeURL: URL) -> URL? {
        let stem = daeURL.deletingPathExtension().lastPathComponent
        let parent = daeURL.deletingLastPathComponent()
        var candidates: [URL] = []
        if parent.lastPathComponent.lowercased() == "visual" {
            let collisionDir = parent.deletingLastPathComponent().appendingPathComponent("collision", isDirectory: true)
            candidates.append(collisionDir.appendingPathComponent("\(stem).stl"))
            candidates.append(collisionDir.appendingPathComponent("\(stem).STL"))
        }
        candidates.append(parent.appendingPathComponent("\(stem).stl"))
        candidates.append(
            parent.deletingLastPathComponent()
                .appendingPathComponent("collision", isDirectory: true)
                .appendingPathComponent("\(stem).stl")
        )
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url.standardizedFileURL
            }
        }
        return nil
    }

    /// Loads DAE via SCNScene. Returns nil on failure without posting Issues (caller handles fallback messaging).
    private func loadDAENode(url: URL) -> SCNNode? {
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
        retainSecurityScopedIfNeeded(url)

        do {
            let options: [SCNSceneSource.LoadingOption: Any] = [
                .assetDirectoryURLs: [url.deletingLastPathComponent()],
                .createNormalsIfAbsent: true,
                .checkConsistency: true,
            ]
            let scene = try SCNScene(url: url, options: options)
            let wrapper = SCNNode()
            wrapper.name = url.lastPathComponent
            for child in scene.rootNode.childNodes {
                wrapper.addChildNode(child.clone())
            }
            if wrapper.childNodes.isEmpty {
                if let geo = scene.rootNode.geometry {
                    wrapper.geometry = geo
                    wrapper.morpher = scene.rootNode.morpher
                } else {
                    return nil
                }
            }
            // Empty visual content still counts as failure for fallback purposes.
            var hasGeometry = wrapper.geometry != nil
            wrapper.enumerateChildNodes { child, _ in
                if child.geometry != nil { hasGeometry = true }
            }
            return hasGeometry ? wrapper : nil
        } catch {
            return nil
        }
    }

    private func nsErrorDetail(_ error: Error) -> String {
        let ns = error as NSError
        var parts = [ns.localizedDescription]
        if ns.domain.isEmpty == false {
            parts.append("domain=\(ns.domain) code=\(ns.code)")
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying: \(underlying.localizedDescription) (\(underlying.domain)/\(underlying.code))")
        }
        return parts.joined(separator: " | ")
    }

    private func appendIssue(
        severity: URDFIssue.Severity,
        file: String?,
        message: String,
        hint: String?
    ) {
        let issue = URDFIssue(
            severity: severity,
            file: file,
            tag: "mesh",
            message: message,
            hint: hint
        )
        if !displayedIssues.contains(where: { $0.message == issue.message && $0.file == issue.file }) {
            displayedIssues.append(issue)
        }
    }

    private func refreshStatusMessage(robotName: String, linkCount: Int, jointCount: Int) {
        let errN = displayedIssues.filter { $0.severity == .error }.count
        let warnN = displayedIssues.filter { $0.severity == .warning }.count
        statusMessage =
            "\(robotName) — \(linkCount) links, \(jointCount) joints"
            + (errN + warnN > 0 ? " · \(errN) errors, \(warnN) warnings" : "")
    }

    private func apply(document doc: URDFDocument, audits: [MeshAudit]) {
        document = doc
        meshAudits = audits
        jointState = .zero(for: doc)
        jointState.clamp(to: doc)
        selectedJointName = nil
        selectedLinkName = nil
        displayedIssues = doc.errors + doc.warnings
        for audit in audits {
            if case let .resolved(url) = audit.resolution {
                retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
                retainSecurityScopedIfNeeded(url)
                _ = nodeForResolvedMesh(url: url)
            }
        }
        // Count includes mesh fallback / load Issues appended during warm cache.
        refreshStatusMessage(
            robotName: doc.robotName,
            linkCount: doc.links.count,
            jointCount: doc.joints.count
        )
        rebuildSceneStructure()
    }

    private func rebuildSceneStructure() {
        sceneEpoch &+= 1
    }

    // MARK: - Security-scoped access (App Sandbox)

    private func beginSecurityScopedAccess(forDocument url: URL) {
        retainSecurityScopedIfNeeded(url)
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent().deletingLastPathComponent())
    }

    private func retainSecurityScopedIfNeeded(_ url: URL) {
        let standardized = url.standardizedFileURL
        if securityScopedURLs.contains(standardized) { return }
        // Returns true only for security-scoped URLs (Open panel / DnD under sandbox).
        if standardized.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(standardized)
        }
    }

    private func releaseSecurityScopedAccess() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    private func mergePackageHint(fromDocumentURL url: URL) {
        let dir = url.deletingLastPathComponent()
        addPackageHint(dir)
        addPackageHint(dir.deletingLastPathComponent())
    }

    func addPackageHint(_ url: URL) {
        let standardized = url.standardizedFileURL
        if !packageHints.contains(standardized) {
            packageHints.append(standardized)
        }
        retainSecurityScopedIfNeeded(standardized)
    }

    private func urdfFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "urdf" {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    deinit {
        // stopAccessing is safe; AppModel is MainActor but deinit may not be — use stored list.
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
