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
    /// ROS/URDF Z-up → SceneKit Y-up (rotate root about X by -π/2). Default ON.
    @Published var useZUpToYUp: Bool = true
    /// Force teal on STL/OBJ mesh materials. OFF → neutral gray.
    @Published var tealMeshTint: Bool = true
    /// Bottom Issues panel visibility (default ON).
    @Published var showIssuesPanel: Bool = true
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
    /// Package roots the user explicitly granted (folder Open / DnD) — never auto-released on file reload.
    private var persistentPackageRoots: [URL] = []

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
        panel.message = "Select a URDF file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url, securityScoped: true)
        // File-only Open does not cover sibling meshes/ under App Sandbox.
        promptPackageRootAccess(suggestedNear: url)
    }

    /// File > Grant Package Folder Access… — e.g. rbpodo_description.
    func grantPackageFolderAccess() {
        let near = openedURL ?? persistentPackageRoots.first
        promptPackageRootAccess(suggestedNear: near)
    }

    func noteOpenedDocument(url: URL?) {
        guard let url else { return }
        load(url: url, securityScoped: true)
        promptPackageRootAccess(suggestedNear: url)
    }

    func load(url: URL, securityScoped: Bool = true) {
        // Keep persistent package roots; only drop ephemeral file scopes.
        releaseEphemeralSecurityScopedAccess()
        if securityScoped {
            beginSecurityScopedAccess(forDocument: url)
        } else {
            beginSecurityScopedAccess(forDocument: url)
        }
        for root in persistentPackageRoots {
            retainSecurityScopedIfNeeded(root)
        }

        openedURL = url
        mergePackageHint(fromDocumentURL: url)
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
        // Folder DnD is the preferred sandbox grant for package:// meshes.
        rememberPackageRoot(folderURL)
        let urdfs = urdfFiles(in: folderURL)
        if urdfs.isEmpty {
            displayedIssues = [
                URDFIssue(
                    severity: .error,
                    file: folderURL.lastPathComponent,
                    message: "폴더에 .urdf 파일이 없습니다",
                    hint: "URDF가 있는 패키지 폴더(예: rbpodo_description)를 드롭하세요"
                ),
            ]
            statusMessage = "No .urdf in folder"
            return
        }
        if urdfs.count > 1 {
            load(url: urdfs[0], securityScoped: true)
            appendIssue(
                severity: .warning,
                file: folderURL.lastPathComponent,
                message: "폴더에 .urdf가 \(urdfs.count)개 있어 첫 파일만 로드했습니다: \(urdfs[0].lastPathComponent)",
                hint: "원하는 파일이면 File > Open으로 직접 선택하세요"
            )
            refreshStatusFromDocument()
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

    func setUseZUpToYUp(_ value: Bool) {
        useZUpToYUp = value
        rebuildSceneStructure()
    }

    func setTealMeshTint(_ value: Bool) {
        tealMeshTint = value
        // Cached STL nodes bake diffuse color — clear so tint reapplies.
        meshNodeCache.removeAll()
        rebuildSceneStructure()
    }

    func setShowIssuesPanel(_ value: Bool) {
        showIssuesPanel = value
    }

    func toggleIssuesPanel() {
        showIssuesPanel.toggle()
    }

    /// Returns a clone of the cached mesh node for a resolved URL (STL/OBJ via MeshLoader, DAE via SCNScene).
    /// Blender COLLADA often fails in SceneKit — on DAE failure, tries `visual/X.dae` → `collision/X.stl`.
    func nodeForResolvedMesh(url: URL) -> SCNNode? {
        if let cached = meshNodeCache[url] {
            let clone = cached.clone()
            applyMeshTint(toNode: clone)
            return clone
        }
        let ext = url.pathExtension.lowercased()
        if ext == "dae" {
            if let node = loadDAENode(url: url) {
                meshNodeCache[url] = node
                let clone = node.clone()
                // DAE keeps embedded materials unless teal tint is forced.
                if tealMeshTint {
                    applyMeshTint(toNode: clone)
                }
                return clone
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
                    let clone = stlNode.clone()
                    applyMeshTint(toNode: clone)
                    return clone
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
        if let node = loadSTLOrOBJNode(url: url) {
            let clone = node.clone()
            applyMeshTint(toNode: clone)
            return clone
        }
        return nil
    }

    private func applyMeshTint(to geometry: SCNGeometry) {
        let color: NSColor = tealMeshTint ? .systemTeal : .lightGray
        geometry.firstMaterial?.diffuse.contents = color
    }

    private func applyMeshTint(toNode node: SCNNode) {
        let color: NSColor = tealMeshTint ? .systemTeal : .lightGray
        node.enumerateHierarchy { child, _ in
            if child.geometry != nil {
                child.geometry?.firstMaterial?.diffuse.contents = color
            }
        }
    }

    func geometryForResolvedMesh(url: URL) -> SCNGeometry? {
        nodeForResolvedMesh(url: url)?.geometry
    }

    private func loadSTLOrOBJNode(url: URL) -> SCNNode? {
        if let cached = meshNodeCache[url] {
            return cached
        }
        // Probe readability under sandbox before MeshLoader.
        do {
            let attrs = try url.resourceValues(forKeys: [.isReadableKey, .fileSizeKey])
            if attrs.isReadable == false {
                appendIssue(
                    severity: .warning,
                    file: url.lastPathComponent,
                    message: "STL 읽기 권한 없음 (샌드박스): \(url.lastPathComponent)",
                    hint: "\(url.path) — 패키지 폴더를 DnD 하거나 File > Grant Package Folder Access…"
                )
                return nil
            }
        } catch {
            appendIssue(
                severity: .warning,
                file: url.lastPathComponent,
                message: "STL 메타데이터 조회 실패: \(url.lastPathComponent)",
                hint: nsErrorDetail(error)
            )
        }
        do {
            // Force Data read so sandbox failures surface as NSError (not silent).
            _ = try Data(contentsOf: url, options: [.mappedIfSafe])
            let buffer = try meshLoader.load(url: url)
            let geo = MeshBufferSceneKit.geometry(from: buffer)
            applyMeshTint(to: geo)
            let node = SCNNode(geometry: geo)
            meshNodeCache[url] = node
            return node
        } catch {
            appendIssue(
                severity: .warning,
                file: url.lastPathComponent,
                message: "STL Data 로드 실패 (샌드박스/POSIX): \(url.lastPathComponent)",
                hint: nsErrorDetail(error) + " | path=\(url.path)"
            )
            return nil
        }
    }

    /// `.../visual/linkN.dae` → `.../collision/linkN.stl` (also same-folder / package-root search).
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
        // Under granted package roots: meshes/<robot>/collision/linkN.stl
        for root in persistentPackageRoots + packageHints {
            candidates.append(
                root.appendingPathComponent("meshes", isDirectory: true)
                    .appendingPathComponent("collision", isDirectory: true)
                    .appendingPathComponent("\(stem).stl")
            )
            // rb layout: meshes/rb16_900e_u/collision/linkN.stl
            let meshes = root.appendingPathComponent("meshes", isDirectory: true)
            if let kids = try? FileManager.default.contentsOfDirectory(
                at: meshes,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for kid in kids {
                    candidates.append(
                        kid.appendingPathComponent("collision", isDirectory: true)
                            .appendingPathComponent("\(stem).stl")
                    )
                }
            }
        }
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url.standardizedFileURL
            }
        }
        // Return best-guess path even if fileExists is false (sandbox can lie) so load error surfaces.
        if parent.lastPathComponent.lowercased() == "visual" {
            return parent
                .deletingLastPathComponent()
                .appendingPathComponent("collision", isDirectory: true)
                .appendingPathComponent("\(stem).stl")
                .standardizedFileURL
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
            displayedIssues = displayedIssues + [issue]
        }
    }

    private func refreshStatusFromDocument() {
        let name = document?.robotName ?? openedURL?.deletingPathExtension().lastPathComponent ?? "—"
        refreshStatusMessage(
            robotName: name,
            linkCount: document?.links.count ?? 0,
            jointCount: document?.joints.count ?? 0
        )
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

    private func promptPackageRootAccess(suggestedNear url: URL?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select package root folder (e.g. rbpodo_description) so visual/collision meshes load under App Sandbox"
        panel.prompt = "Grant Access"
        if let url {
            // robots/foo.urdf → often …/rbpodo_description/
            panel.directoryURL = url
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        // Non-blocking feel: still modal, cancel is OK (user can DnD folder later).
        guard panel.runModal() == .OK, let dir = panel.url else {
            appendIssue(
                severity: .warning,
                file: openedURL?.lastPathComponent,
                message: "패키지 폴더 권한이 없습니다 — meshes/collision STL이 샌드박스에 막힐 수 있습니다",
                hint: "File > Grant Package Folder Access… 또는 rbpodo_description 폴더를 창에 드롭하세요"
            )
            refreshStatusFromDocument()
            return
        }
        rememberPackageRoot(dir)
        remountMeshesAfterPackageGrant()
    }

    private func rememberPackageRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        retainSecurityScopedIfNeeded(standardized)
        if !persistentPackageRoots.contains(standardized) {
            persistentPackageRoots.append(standardized)
        }
        addPackageHint(standardized)
        // Also hint common children
        addPackageHint(standardized.appendingPathComponent("meshes", isDirectory: true))
        appendIssue(
            severity: .warning,
            file: standardized.lastPathComponent,
            message: "패키지 폴더 접근 허용: \(standardized.lastPathComponent)",
            hint: standardized.path
        )
    }

    /// Clear mesh cache and re-audit/reload meshes with current package access.
    private func remountMeshesAfterPackageGrant() {
        guard let url = openedURL else {
            refreshStatusFromDocument()
            rebuildSceneStructure()
            return
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
            appendIssue(
                severity: .error,
                file: url.lastPathComponent,
                message: "패키지 권한 후 재로드 실패: \(error.localizedDescription)",
                hint: nil
            )
            refreshStatusFromDocument()
            rebuildSceneStructure()
        }
    }

    private func beginSecurityScopedAccess(forDocument url: URL) {
        retainSecurityScopedIfNeeded(url)
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent())
        retainSecurityScopedIfNeeded(url.deletingLastPathComponent().deletingLastPathComponent())
    }

    @discardableResult
    private func retainSecurityScopedIfNeeded(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        if securityScopedURLs.contains(standardized) { return true }
        if standardized.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(standardized)
            return true
        }
        return false
    }

    /// Releases scopes that are not in persistentPackageRoots.
    private func releaseEphemeralSecurityScopedAccess() {
        let keep = Set(persistentPackageRoots.map(\.standardizedFileURL))
        var kept: [URL] = []
        for url in securityScopedURLs {
            let s = url.standardizedFileURL
            if keep.contains(s) {
                kept.append(s)
            } else {
                url.stopAccessingSecurityScopedResource()
            }
        }
        securityScopedURLs = kept
    }

    private func releaseSecurityScopedAccess() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
        persistentPackageRoots.removeAll()
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
