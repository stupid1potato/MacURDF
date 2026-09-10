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
        useZUpToYUp: Bool,
        tealMeshTint: Bool,
        meshNode: (URL) -> SCNNode?
    ) -> SCNScene {
        let scene = ViewportScene.makeBaseEnvironment()
        guard let document else {
            scene.rootNode.addChildNode(ViewportScene.placeholderCube())
            return scene
        }
        scene.rootNode.addChildNode(
            makeRobotRoot(
                document: document,
                audits: audits,
                transforms: transforms,
                showVisual: showVisual,
                showCollision: showCollision,
                selectedLinkName: selectedLinkName,
                useZUpToYUp: useZUpToYUp,
                tealMeshTint: tealMeshTint,
                meshNode: meshNode
            )
        )
        return scene
    }

    /// Returns world-correction wrapper (`URDFWorldCorrection`) containing robot root named `document.robotName`.
    /// Link FK transforms stay on link nodes; Z-up→Y-up is only on the wrapper.
    static func makeRobotRoot(
        document: URDFDocument,
        audits: [MeshAudit],
        transforms: [String: simd_float4x4],
        showVisual: Bool,
        showCollision: Bool,
        selectedLinkName: String?,
        useZUpToYUp: Bool,
        tealMeshTint: Bool,
        meshNode: (URL) -> SCNNode?
    ) -> SCNNode {
        let auditByLinkFile: [String: MeshResolution] = {
            var map: [String: MeshResolution] = [:]
            for a in audits {
                map["\(a.linkName)|\(a.filename)"] = a.resolution
            }
            return map
        }()

        let robotRoot = SCNNode()
        robotRoot.name = document.robotName

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
                        link: link,
                        auditMap: auditByLinkFile,
                        color: .systemGray,
                        meshNode: meshNode,
                        preserveMaterials: false
                    )
                    geo.name = "\(link.name)_visual_fallback"
                    linkNode.addChildNode(geo)
                } else {
                    for (idx, visual) in visuals.enumerated() {
                        let geo = node(
                            for: visual.geometry,
                            linkName: link.name,
                            link: link,
                            auditMap: auditByLinkFile,
                            color: tealMeshTint ? .systemTeal : .lightGray,
                            meshNode: meshNode,
                            preserveMaterials: true
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
                        link: link,
                        auditMap: auditByLinkFile,
                        color: NSColor.systemOrange.withAlphaComponent(0.45),
                        meshNode: meshNode,
                        preserveMaterials: false
                    )
                    geo.name = "\(link.name)_collision_\(idx)"
                    geo.simdTransform = PoseMath.matrix(from: collision.origin)
                    geo.enumerateHierarchy { child, _ in
                        child.geometry?.firstMaterial?.transparency = 0.45
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

        let world = SCNNode()
        world.name = "URDFWorldCorrection"
        if useZUpToYUp {
            // URDF/ROS Z-up → SceneKit Y-up
            world.simdOrientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        }
        world.addChildNode(robotRoot)
        return world
    }

    /// `.../visual/linkN.dae` → `.../collision/linkN.stl`
    static func collisionSTLURL(fromVisualDAE daeURL: URL) -> URL? {
        let stem = daeURL.deletingPathExtension().lastPathComponent
        let parent = daeURL.deletingLastPathComponent()
        var candidates: [URL] = []
        if parent.lastPathComponent.lowercased() == "visual" {
            let collisionDir = parent
                .deletingLastPathComponent()
                .appendingPathComponent("collision", isDirectory: true)
            candidates.append(collisionDir.appendingPathComponent("\(stem).stl"))
            candidates.append(collisionDir.appendingPathComponent("\(stem).STL"))
        }
        candidates.append(parent.appendingPathComponent("\(stem).stl"))
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url.standardizedFileURL
        }
        return nil
    }

    private static func collisionMeshFallback(
        link: Link,
        auditMap: [String: MeshResolution],
        meshNode: (URL) -> SCNNode?
    ) -> SCNNode? {
        for collision in link.collisions {
            guard case let .mesh(filename, scale) = collision.geometry else { continue }
            let key = "\(link.name)|\(filename)"
            if case let .resolved(url) = auditMap[key], let n = meshNode(url) {
                if let scale {
                    n.scale = SCNVector3(scale.x, scale.y, scale.z)
                }
                return n
            }
        }
        return nil
    }

    private static func node(
        for geometry: Geometry,
        linkName: String,
        link: Link?,
        auditMap: [String: MeshResolution],
        color: NSColor,
        meshNode: (URL) -> SCNNode?,
        preserveMaterials: Bool
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
            var loaded: SCNNode?

            if case let .resolved(url) = resolution {
                loaded = meshNode(url)
                // Extra path-rewrite if DAE key somehow not cached with STL yet
                if loaded == nil, url.pathExtension.lowercased() == "dae",
                   let stl = collisionSTLURL(fromVisualDAE: url) {
                    loaded = meshNode(stl)
                }
            }

            if loaded == nil,
               filename.lowercased().hasSuffix(".dae"),
               let link,
               let fallback = collisionMeshFallback(
                link: link,
                auditMap: auditMap,
                meshNode: meshNode
               ) {
                loaded = fallback
            }

            if let n = loaded {
                if !preserveMaterials {
                    n.enumerateHierarchy { child, _ in
                        child.geometry?.firstMaterial?.diffuse.contents = color
                    }
                }
                if let scale {
                    n.scale = SCNVector3(
                        n.scale.x * CGFloat(scale.x),
                        n.scale.y * CGFloat(scale.y),
                        n.scale.z * CGFloat(scale.z)
                    )
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
            n.name = "meshPlaceholder"
            if let scale {
                n.scale = SCNVector3(scale.x, scale.y, scale.z)
            }
            return n
        }
    }
}
