import AppKit
import SceneKit
import SwiftUI
import URDFCore

struct SceneViewportView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SceneViewRepresentable(
            scene: RobotSceneBuilder.buildScene(
                document: appModel.document,
                audits: appModel.meshAudits,
                transforms: appModel.linkTransforms,
                showVisual: appModel.showVisual,
                showCollision: appModel.showCollision,
                selectedLinkName: appModel.selectedLinkName,
                meshGeometry: { appModel.geometryForResolvedMesh(url: $0) }
            )
        )
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .topLeading) {
            Text(appModel.document?.robotName ?? "3D Viewport")
                .font(.caption)
                .padding(8)
                .foregroundStyle(.secondary)
        }
        .id(appModel.sceneEpoch)
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
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        if let camera = scene.rootNode.childNode(withName: "MainCamera", recursively: false) {
            view.pointOfView = camera
        }
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let pov = nsView.pointOfView
        nsView.scene = scene
        if let camera = scene.rootNode.childNode(withName: "MainCamera", recursively: false) {
            nsView.pointOfView = pov ?? camera
        }
    }
}
