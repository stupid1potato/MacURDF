import AppKit
import SceneKit
import SwiftUI
import simd
import URDFCore

struct SceneViewportView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SceneViewRepresentable(
            sceneEpoch: appModel.sceneEpoch,
            jointState: appModel.jointState,
            document: appModel.document,
            audits: appModel.meshAudits,
            showVisual: appModel.showVisual,
            showCollision: appModel.showCollision,
            selectedLinkName: appModel.selectedLinkName,
            linkTransforms: appModel.linkTransforms,
            meshNode: { appModel.nodeForResolvedMesh(url: $0) }
        )
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .topLeading) {
            Text(appModel.document?.robotName ?? "3D Viewport")
                .font(.caption)
                .padding(8)
                .foregroundStyle(.secondary)
        }
        // Do NOT use .id(sceneEpoch) — that destroys SCNView and resets the camera.
    }
}

enum ViewportScene {
    static func makeBaseEnvironment() -> SCNScene {
        let scene = SCNScene()

        let ambient = SCNNode()
        ambient.light = {
            let l = SCNLight()
            l.type = .ambient
            l.intensity = 400
            return l
        }()
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = {
            let l = SCNLight()
            l.type = .directional
            l.intensity = 800
            l.castsShadow = true
            return l
        }()
        sun.eulerAngles = SCNVector3(-0.8, 0.4, 0)
        scene.rootNode.addChildNode(sun)

        scene.rootNode.addChildNode(gridNode(size: 20, step: 1))
        scene.rootNode.addChildNode(axisNode())

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = 200
        camera.position = SCNVector3(2.5, 2.0, 4.0)
        camera.look(at: SCNVector3(0, 0.2, 0))
        camera.name = "MainCamera"
        scene.rootNode.addChildNode(camera)

        return scene
    }

    static func placeholderCube() -> SCNNode {
        let cube = SCNNode(geometry: SCNBox(width: 0.4, height: 0.4, length: 0.4, chamferRadius: 0.02))
        cube.geometry?.firstMaterial?.diffuse.contents = NSColor.systemTeal
        cube.position = SCNVector3(0, 0.2, 0)
        cube.name = "PlaceholderLink"
        return cube
    }

    private static func gridNode(size: Int, step: Int) -> SCNNode {
        let parent = SCNNode()
        parent.name = "Grid"
        let half = Double(size) / 2.0
        let color = NSColor.gray.withAlphaComponent(0.35)
        for i in stride(from: -size / 2, through: size / 2, by: step) {
            let t = Double(i)
            parent.addChildNode(line(from: SCNVector3(-half, 0, t), to: SCNVector3(half, 0, t), color: color))
            parent.addChildNode(line(from: SCNVector3(t, 0, -half), to: SCNVector3(t, 0, half), color: color))
        }
        return parent
    }

    private static func axisNode() -> SCNNode {
        let parent = SCNNode()
        parent.name = "WorldAxes"
        let len: Double = 1.0
        parent.addChildNode(line(from: .init(0, 0, 0), to: .init(len, 0, 0), color: .systemRed))
        parent.addChildNode(line(from: .init(0, 0, 0), to: .init(0, len, 0), color: .systemGreen))
        parent.addChildNode(line(from: .init(0, 0, 0), to: .init(0, 0, len), color: .systemBlue))
        return parent
    }

    private static func line(from: SCNVector3, to: SCNVector3, color: NSColor) -> SCNNode {
        let positions = [from, to]
        let source = SCNGeometrySource(vertices: positions)
        let indices: [UInt8] = [0, 1]
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geo = SCNGeometry(sources: [source], elements: [element])
        geo.firstMaterial?.diffuse.contents = color
        geo.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: geo)
    }
}

struct SceneViewRepresentable: NSViewRepresentable {
    var sceneEpoch: Int
    var jointState: JointState
    var document: URDFDocument?
    var audits: [MeshAudit]
    var showVisual: Bool
    var showCollision: Bool
    var selectedLinkName: String?
    var linkTransforms: [String: simd_float4x4]
    var meshNode: (URL) -> SCNNode?

    final class Coordinator {
        var appliedEpoch: Int = -1
        /// linkName -> SCNNode under robot root
        var linkNodes: [String: SCNNode] = [:]
        var robotRootName: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        rebuild(view: view, context: context, preserveCamera: false)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if context.coordinator.appliedEpoch != sceneEpoch {
            rebuild(view: nsView, context: context, preserveCamera: true)
            return
        }
        // FK-only: update existing link node transforms (no SCNScene swap).
        applyTransforms(context.coordinator)
    }

    private func rebuild(view: SCNView, context: Context, preserveCamera: Bool) {
        let scene: SCNScene
        if let existing = view.scene, preserveCamera {
            scene = existing
            // Drop previous robot roots / placeholders; keep lights, grid, camera.
            let removable = scene.rootNode.childNodes.filter { node in
                let n = node.name ?? ""
                return n != "MainCamera" && n != "Grid" && n != "WorldAxes"
                    && node.light == nil
            }
            removable.forEach { $0.removeFromParentNode() }
            if let doc = document {
                scene.rootNode.addChildNode(
                    RobotSceneBuilder.makeRobotRoot(
                        document: doc,
                        audits: audits,
                        transforms: linkTransforms,
                        showVisual: showVisual,
                        showCollision: showCollision,
                        selectedLinkName: selectedLinkName,
                        meshNode: meshNode
                    )
                )
            } else {
                scene.rootNode.addChildNode(ViewportScene.placeholderCube())
            }
        } else {
            scene = RobotSceneBuilder.buildScene(
                document: document,
                audits: audits,
                transforms: linkTransforms,
                showVisual: showVisual,
                showCollision: showCollision,
                selectedLinkName: selectedLinkName,
                meshNode: meshNode
            )
            view.scene = scene
            if let cam = scene.rootNode.childNode(withName: "MainCamera", recursively: false) {
                view.pointOfView = cam
            }
        }

        var map: [String: SCNNode] = [:]
        if let doc = document {
            let root = scene.rootNode.childNode(withName: doc.robotName, recursively: false)
            context.coordinator.robotRootName = doc.robotName
            if let root {
                for link in doc.links {
                    if let node = root.childNode(withName: link.name, recursively: false) {
                        map[link.name] = node
                    }
                }
            }
        } else {
            context.coordinator.robotRootName = nil
        }
        context.coordinator.linkNodes = map
        context.coordinator.appliedEpoch = sceneEpoch
    }

    private func applyTransforms(_ coordinator: Coordinator) {
        for (name, node) in coordinator.linkNodes {
            node.simdTransform = linkTransforms[name] ?? matrix_identity_float4x4
        }
    }
}
