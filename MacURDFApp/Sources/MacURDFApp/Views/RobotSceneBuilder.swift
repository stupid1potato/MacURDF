import AppKit
import Foundation
import SceneKit
import simd
import URDFCore

enum RobotSceneBuilder {
    static func buildScene(
        document: URDFDocument?,
        audits: [MeshAudit],
        transforms: [String: simd_float4x4],
        showVisual: Bool,
        showCollision: Bool,
        selectedLinkName: String?,
        meshGeometry: (URL) -> SCNGeometry?
    ) -> SCNScene {
        let scene = ViewportScene.makeBaseEnvironment()

        guard let document else {
            scene.rootNode.addChildNode(ViewportScene.placeholderCube())
            return scene
        }

        let auditByLinkFile: [String: MeshResolution] = {
            var map: [String: MeshResolution] = [:]
            for a in audits {
                map["\(a.linkName)|\(a.filename)"] = a.resolution
            }
            return map
        }()

        let robotRoot = SCNNode()
        robotRoot.name = document.robotName
        scene.rootNode.addChildNode(robotRoot)

        for link in document.links {
            let linkNode = SCNNode()
            linkNode.name = link.name
            linkNode.simdTransform = transforms[link.name] ?? matrix_identity_float4x4

            if showVisual {
                let visuals = link.visuals
                if visuals.isEmpty {
                    let geo = node(
                        for: .box(size: SIMD3(0.05, 0.05, 0.05)),
                        linkName: link.name,
                        auditMap: auditByLinkFile,
                        color: .systemGray,
                        meshGeometry: meshGeometry
                    )
                    geo.name = "\(link.name)_visual_fallback"
                    linkNode.addChildNode(geo)
                } else {
                    for (idx, visual) in visuals.enumerated() {
                        let geo = node(
                            for: visual.geometry,
                            linkName: link.name,
                            auditMap: auditByLinkFile,
                            color: .systemTeal,
                            meshGeometry: meshGeometry
                        )
                        geo.name = "\(link.name)_visual_\(idx)"
                        geo.simdTransform = PoseMath.matrix(from: visual.origin)
                        linkNode.addChildNode(geo)
                    }
                }
            }

            if showCollision {
                for (idx, collision) in link.collisions.enumerated() {
                    let geo = node(
                        for: collision.geometry,
                        linkName: link.name,
                        auditMap: auditByLinkFile,
                        color: NSColor.systemOrange.withAlphaComponent(0.45),
                        meshGeometry: meshGeometry
                    )
                    geo.name = "\(link.name)_collision_\(idx)"
                    geo.simdTransform = PoseMath.matrix(from: collision.origin)
                    if let m = geo.geometry?.firstMaterial {
                        m.transparency = 0.45
                    }
                    linkNode.addChildNode(geo)
                }
            }

            if selectedLinkName == link.name {
                let halo = SCNNode(geometry: SCNSphere(radius: 0.06))
                halo.geometry?.firstMaterial?.diffuse.contents = NSColor.systemYellow
                halo.geometry?.firstMaterial?.transparency = 0.35
                halo.name = "selectionHalo"
                linkNode.addChildNode(halo)
            }

            robotRoot.addChildNode(linkNode)
        }

        return scene
    }

    private static func node(
        for geometry: Geometry,
        linkName: String,
        auditMap: [String: MeshResolution],
        color: NSColor,
        meshGeometry: (URL) -> SCNGeometry?
    ) -> SCNNode {
        switch geometry {
        case let .box(size):
            let box = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0
            )
            box.firstMaterial?.diffuse.contents = color
            return SCNNode(geometry: box)

        case let .cylinder(radius, length):
            let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
            cyl.firstMaterial?.diffuse.contents = color
            let n = SCNNode(geometry: cyl)
            n.eulerAngles = SCNVector3(Double.pi / 2, 0, 0)
            return n

        case let .sphere(radius):
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.firstMaterial?.diffuse.contents = color
            return SCNNode(geometry: sphere)

        case let .mesh(filename, scale):
            let key = "\(linkName)|\(filename)"
            let resolution = auditMap[key]
            if case let .resolved(url) = resolution, let geo = meshGeometry(url) {
                let n = SCNNode(geometry: geo.copy() as? SCNGeometry ?? geo)
                n.geometry?.firstMaterial?.diffuse.contents = color
                if let scale {
                    n.scale = SCNVector3(scale.x, scale.y, scale.z)
                }
                return n
            }
            let placeholderColor: NSColor
            switch resolution {
            case .resolved?:
                placeholderColor = .systemYellow
            case .unsupported?:
                placeholderColor = .systemOrange
            case .missing?, .none:
                placeholderColor = .systemRed
            }
            let box = SCNBox(width: 0.2, height: 0.2, length: 0.2, chamferRadius: 0.01)
            box.firstMaterial?.diffuse.contents = placeholderColor
            let n = SCNNode(geometry: box)
            if let scale {
                n.scale = SCNVector3(scale.x, scale.y, scale.z)
            }
            return n
        }
    }
}
