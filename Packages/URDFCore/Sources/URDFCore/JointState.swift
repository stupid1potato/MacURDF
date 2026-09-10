import Foundation

public struct JointState: Sendable {
    /// jointName -> position (rad or m)
    public var values: [String: Double]

    public init(values: [String: Double] = [:]) {
        self.values = values
    }
}

public extension JointState {
    static func zero(for document: URDFDocument) -> JointState {
        var values: [String: Double] = [:]
        for joint in document.joints {
            values[joint.name] = 0
        }
        return JointState(values: values)
    }

    mutating func clamp(to document: URDFDocument) {
        for joint in document.joints {
            guard let limit = joint.limit else { continue }
            switch joint.type {
            case .revolute, .prismatic:
                if let current = values[joint.name] {
                    values[joint.name] = min(max(current, limit.lower), limit.upper)
                }
            case .continuous, .fixed, .floating, .planar:
                break
            }
        }
    }
}
