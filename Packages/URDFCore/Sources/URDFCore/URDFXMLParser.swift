import Foundation
import simd

/// Foundation XMLParser based URDF reader. No third-party XML libs.
final class URDFXMLParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private(set) var robotName = ""
    private(set) var links: [Link] = []
    private(set) var joints: [Joint] = []
    private(set) var warnings: [URDFIssue] = []
    private(set) var errors: [URDFIssue] = []
    private(set) var fatalParseError: Error?

    private var sourceFile: String?
    private var elementStack: [String] = []
    private var currentLine: Int?

    // Link building
    private var linkName: String?
    private var linkVisuals: [Visual] = []
    private var linkCollisions: [Collision] = []

    // Shared origin/geometry for visual|collision
    private var pendingOrigin: Pose = .identity
    private var pendingGeometry: Geometry?
    private var pendingMaterialName: String?
    private var inVisual = false
    private var inCollision = false
    private var inGeometry = false

    // Joint building
    private var jointName: String?
    private var jointTypeRaw: String?
    private var jointParent: String?
    private var jointChild: String?
    private var jointOrigin: Pose = .identity
    private var jointAxis: SIMD3<Double> = SIMD3(0, 0, 1)
    private var jointLimit: JointLimit?

    /// Skip kinematic parsing inside ros2_control / transmission / gazebo subtrees.
    private var ignoreSubtreeDepth = 0
    private static let nonKinematicRoots: Set<String> = [
        "ros2_control", "transmission", "gazebo"
    ]

    func parse(data: Data, sourceFile: String?) {
        self.sourceFile = sourceFile
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        if !parser.parse() {
            if let err = parser.parserError {
                fatalParseError = err
            }
        }
    }

    private func issue(
        _ severity: URDFIssue.Severity,
        tag: String?,
        message: String,
        hint: String? = nil
    ) {
        let item = URDFIssue(
            severity: severity,
            file: sourceFile,
            line: currentLine,
            tag: tag,
            message: message,
            hint: hint
        )
        switch severity {
        case .error: errors.append(item)
        case .warning: warnings.append(item)
        }
    }

    private func parseVec3(_ raw: String?, default defaultValue: SIMD3<Double> = .zero) -> SIMD3<Double>? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        let parts = raw.split(whereSeparator: { $0.isWhitespace }).compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return SIMD3(parts[0], parts[1], parts[2])
    }

    private func parseDouble(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentLine = parser.lineNumber
        let tag = elementName.lowercased()
        elementStack.append(tag)

        if ignoreSubtreeDepth > 0 {
            ignoreSubtreeDepth += 1
            return
        }
        if Self.nonKinematicRoots.contains(tag) {
            ignoreSubtreeDepth = 1
            return
        }

        switch tag {
        case "robot":
            if let name = attributeDict["name"], !name.isEmpty {
                robotName = name
            } else {
                issue(.error, tag: tag, message: "robot name 속성이 없습니다")
            }

        case "xacro:macro", "xacro:include", "xacro:property":
            issue(
                .error,
                tag: tag,
                message: "xacro는 v0.1 미지원",
                hint: "xacro를 urdf로 전처리하세요"
            )

        case "link":
            if let name = attributeDict["name"], !name.isEmpty {
                linkName = name
            } else {
                issue(.error, tag: tag, message: "link name 속성이 없습니다")
                linkName = nil
            }
            linkVisuals = []
            linkCollisions = []

        case "visual":
            inVisual = true
            pendingOrigin = .identity
            pendingGeometry = nil
            pendingMaterialName = nil

        case "collision":
            inCollision = true
            pendingOrigin = .identity
            pendingGeometry = nil

        case "origin":
            let xyz = parseVec3(attributeDict["xyz"]) ?? .zero
            let rpy = parseVec3(attributeDict["rpy"]) ?? .zero
            if parseVec3(attributeDict["xyz"]) == nil && attributeDict["xyz"] != nil {
                issue(.error, tag: tag, message: "origin xyz 형식이 올바르지 않습니다")
            }
            let pose = Pose(xyz: xyz, rpy: rpy)
            if inVisual || inCollision {
                pendingOrigin = pose
            } else if jointName != nil {
                jointOrigin = pose
            }

        case "geometry":
            inGeometry = true

        case "box":
            guard inGeometry else { return }
            if let size = parseVec3(attributeDict["size"]) {
                pendingGeometry = .box(size: size)
            } else {
                issue(.error, tag: tag, message: "box size 속성이 없거나 형식이 올바르지 않습니다")
            }

        case "cylinder":
            guard inGeometry else { return }
            let radius = parseDouble(attributeDict["radius"])
            let length = parseDouble(attributeDict["length"])
            if let radius, let length {
                pendingGeometry = .cylinder(radius: radius, length: length)
            } else {
                issue(.error, tag: tag, message: "cylinder radius/length 속성이 필요합니다")
            }

        case "sphere":
            guard inGeometry else { return }
            if let radius = parseDouble(attributeDict["radius"]) {
                pendingGeometry = .sphere(radius: radius)
            } else {
                issue(.error, tag: tag, message: "sphere radius 속성이 없습니다")
            }

        case "mesh":
            guard inGeometry else { return }
            let filename = attributeDict["filename"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if filename.isEmpty {
                issue(.error, tag: tag, message: "mesh filename이 비어 있습니다")
            } else {
                let scale = parseVec3(attributeDict["scale"], default: SIMD3(1, 1, 1))
                pendingGeometry = .mesh(filename: filename, scale: scale)
            }

        case "material":
            if inVisual {
                pendingMaterialName = attributeDict["name"]
            }

        case "joint":
            jointName = attributeDict["name"]
            jointTypeRaw = attributeDict["type"]
            jointParent = nil
            jointChild = nil
            jointOrigin = .identity
            jointAxis = SIMD3(0, 0, 1)
            jointLimit = nil
            if jointName == nil || jointName?.isEmpty == true {
                issue(.error, tag: tag, message: "joint name 속성이 없습니다")
            }
            if jointTypeRaw == nil || jointTypeRaw?.isEmpty == true {
                issue(.error, tag: tag, message: "joint type 속성이 없습니다")
            }

        case "parent":
            jointParent = attributeDict["link"]
            if jointParent == nil || jointParent?.isEmpty == true {
                issue(.error, tag: tag, message: "parent link 속성이 없습니다")
            }

        case "child":
            jointChild = attributeDict["link"]
            if jointChild == nil || jointChild?.isEmpty == true {
                issue(.error, tag: tag, message: "child link 속성이 없습니다")
            }

        case "axis":
            if let axis = parseVec3(attributeDict["xyz"], default: SIMD3(0, 0, 1)) {
                jointAxis = axis
            } else {
                issue(.error, tag: tag, message: "axis xyz 형식이 올바르지 않습니다")
            }

        case "limit":
            let lower = parseDouble(attributeDict["lower"]) ?? 0
            let upper = parseDouble(attributeDict["upper"]) ?? 0
            let effort = parseDouble(attributeDict["effort"]) ?? 0
            let velocity = parseDouble(attributeDict["velocity"]) ?? 0
            jointLimit = JointLimit(lower: lower, upper: upper, effort: effort, velocity: velocity)

        default:
            // Ignore unknown tags (urdf extensibility).
            if tag.hasPrefix("xacro") {
                issue(
                    .error,
                    tag: tag,
                    message: "xacro는 v0.1 미지원",
                    hint: "xacro를 urdf로 전처리하세요"
                )
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        currentLine = parser.lineNumber
        let tag = elementName.lowercased()
        if elementStack.last == tag {
            elementStack.removeLast()
        }

        if ignoreSubtreeDepth > 0 {
            ignoreSubtreeDepth -= 1
            return
        }

        switch tag {
        case "geometry":
            inGeometry = false

        case "visual":
            if let geometry = pendingGeometry {
                linkVisuals.append(
                    Visual(
                        origin: pendingOrigin,
                        geometry: geometry,
                        materialName: pendingMaterialName
                    )
                )
            } else {
                issue(.error, tag: tag, message: "visual에 geometry가 없습니다")
            }
            inVisual = false
            pendingGeometry = nil
            pendingMaterialName = nil
            pendingOrigin = .identity

        case "collision":
            if let geometry = pendingGeometry {
                linkCollisions.append(
                    Collision(origin: pendingOrigin, geometry: geometry)
                )
            } else {
                issue(.error, tag: tag, message: "collision에 geometry가 없습니다")
            }
            inCollision = false
            pendingGeometry = nil
            pendingOrigin = .identity

        case "link":
            if let name = linkName, !name.isEmpty {
                links.append(
                    Link(name: name, visuals: linkVisuals, collisions: linkCollisions)
                )
            }
            linkName = nil
            linkVisuals = []
            linkCollisions = []

        case "joint":
            defer {
                jointName = nil
                jointTypeRaw = nil
                jointParent = nil
                jointChild = nil
            }
            guard let name = jointName, !name.isEmpty else { return }
            guard let parent = jointParent, !parent.isEmpty else { return }
            guard let child = jointChild, !child.isEmpty else { return }
            let raw = jointTypeRaw ?? ""
            let resolvedType: JointType
            if let known = JointType(rawValue: raw) {
                resolvedType = known
            } else {
                issue(.warning, tag: tag, message: "알 수 없는 joint type: \(raw)")
                resolvedType = .fixed
            }
            joints.append(
                Joint(
                    name: name,
                    type: resolvedType,
                    parent: parent,
                    child: child,
                    origin: jointOrigin,
                    axis: jointAxis,
                    limit: jointLimit
                )
            )

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        fatalParseError = parseError
        issue(
            .error,
            tag: nil,
            message: "XML 파싱 실패: \(parseError.localizedDescription)"
        )
    }
}
