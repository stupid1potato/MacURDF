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
    /// Bumped to force SceneKit rebuild.
    @Published private(set) var sceneEpoch: Int = 0

    private let loader = URDFLoader()
    private let meshResolver = LocalMeshResolver()
    private let fk = ForwardKinematics()
    private let meshLoader = MeshLoader()

    /// Cached mesh geometries by resolved file URL.
    private var meshGeometryCache: [URL: SCNGeometry] = [:]

    var linkTransforms: [String: simd_float4x4] {
        guard let doc = document else { return [:] }
        return fk.transforms(document: doc, state: jointState)
    }

    func openURDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.urdf, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a URDF file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func noteOpenedDocument(url: URL?) {
        guard let url else { return }
        load(url: url)
    }

    func load(url: URL) {
        openedURL = url
        mergePackageHint(fromDocumentURL: url)
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
            rebuildScene()
        }
    }

    func loadFromFolder(_ folderURL: URL) {
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
            load(url: urdfs[0])
            let warn = URDFIssue(
                severity: .warning,
                file: folderURL.lastPathComponent,
                message: "폴더에 .urdf가 \(urdfs.count)개 있어 첫 파일만 로드했습니다: \(urdfs[0].lastPathComponent)",
                hint: "원하는 파일이면 File > Open으로 직접 선택하세요"
            )
            displayedIssues = [warn] + displayedIssues
            return
        }
        load(url: urdfs[0])
    }

    func reload() {
        guard let url = openedURL else {
            statusMessage = "Reload — no file open"
            return
        }
        load(url: url)
    }

    func setJoint(_ name: String, value: Double) {
        guard document != nil else { return }
        jointState.values[name] = value
        jointState.clamp(to: document!)
        rebuildScene()
    }

    func selectJoint(_ name: String?) {
        selectedJointName = name
        if let name, let doc = document,
           let joint = doc.joints.first(where: { $0.name == name }) {
            selectedLinkName = joint.child
        }
        rebuildScene()
    }

    func selectLink(_ name: String?) {
        selectedLinkName = name
        rebuildScene()
    }

    func toggleVisual() {
        showVisual.toggle()
        rebuildScene()
    }

    func toggleCollision() {
        showCollision.toggle()
        rebuildScene()
    }

    func setShowVisual(_ value: Bool) {
        showVisual = value
        rebuildScene()
    }

    func setShowCollision(_ value: Bool) {
        showCollision = value
        rebuildScene()
    }

    func geometryForResolvedMesh(url: URL) -> SCNGeometry? {
        if let cached = meshGeometryCache[url] { return cached }
        do {
            let buffer = try meshLoader.load(url: url)
            let geo = MeshBufferSceneKit.geometry(from: buffer)
            geo.firstMaterial?.diffuse.contents = NSColor.systemTeal
            meshGeometryCache[url] = geo
            return geo
        } catch {
            return nil
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
        // Warm mesh cache for resolved audits
        for audit in audits {
            if case let .resolved(url) = audit.resolution {
                _ = geometryForResolvedMesh(url: url)
            }
        }
        rebuildScene()
    }

    private func rebuildScene() {
        sceneEpoch &+= 1
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
}
