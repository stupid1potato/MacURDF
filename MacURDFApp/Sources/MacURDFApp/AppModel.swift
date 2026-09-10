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
            return nil
        }
        do {
            let buffer = try meshLoader.load(url: url)
            let geo = MeshBufferSceneKit.geometry(from: buffer)
            geo.firstMaterial?.diffuse.contents = NSColor.systemTeal
            let node = SCNNode(geometry: geo)
            meshNodeCache[url] = node
            return node.clone()
        } catch {
            appendMeshLoadWarning(url: url, detail: nsErrorDetail(error))
            return nil
        }
    }

    func geometryForResolvedMesh(url: URL) -> SCNGeometry? {
        nodeForResolvedMesh(url: url)?.geometry
    }

    private func loadDAENode(url: URL) -> SCNNode? {
        // Ensure parent directory is accessible under sandbox.
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
                    appendMeshLoadWarning(
                        url: url,
                        detail: "씬에 표시할 노드/지오메트리가 없습니다. 폴더를 Open/DnD 해 패키지 권한을 주세요."
                    )
                    return nil
                }
            }
            return wrapper
        } catch {
            let detail = nsErrorDetail(error)
            let sandboxHint =
                detail.localizedCaseInsensitiveContains("permission")
                || detail.localizedCaseInsensitiveContains("sandbox")
                || detail.localizedCaseInsensitiveContains("not permitted")
                || (error as NSError).domain == NSCocoaErrorDomain
            appendMeshLoadWarning(
                url: url,
                detail: sandboxHint
                    ? "\(detail) — 샌드박스일 수 있음. URDF가 있는 패키지 폴더를 창에 드롭하거나 File > Open으로 열어 권한을 부여하세요."
                    : detail
            )
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

    private func appendMeshLoadWarning(url: URL, detail: String) {
        let issue = URDFIssue(
            severity: .warning,
            file: url.lastPathComponent,
            tag: "mesh",
            message: "메시 로드 실패: \(url.lastPathComponent)",
            hint: detail
        )
        if !displayedIssues.contains(where: { $0.message == issue.message && $0.file == issue.file }) {
            displayedIssues.append(issue)
        }
    }

    private func apply(document doc: URDFDocument, audits: [MeshAudit]) {
        document = doc
        meshAudits = audits
        jointState = .zero(for: doc)
        jointState.clamp(to: doc)
        selectedJointName = nil
        selectedLinkName = nil
        displayedIssues = doc.errors + doc.warnings
        let errN = doc.errors.count
        let warnN = doc.warnings.count
        statusMessage =
            "\(doc.robotName) — \(doc.links.count) links, \(doc.joints.count) joints"
            + (errN + warnN > 0 ? " · \(errN) errors, \(warnN) warnings" : "")
        for audit in audits {
            if case let .resolved(url) = audit.resolution {
                retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
                _ = nodeForResolvedMesh(url: url)
            }
        }
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
