import Foundation
import simd

public struct JointLimit: Sendable, Equatable {
    public var lower: Double
    public var upper: Double
    public var effort: Double
    public var velocity: Double

    public init(lower: Double, upper: Double, effort: Double, velocity: Double) {
        self.lower = lower
        self.upper = upper
        self.effort = effort
        self.velocity = velocity
    }
}

public enum JointType: String, Sendable, Equatable {
    case revolute
    case prismatic
    case continuous
    case fixed
    case floating
    case planar
}

public struct Joint: Sendable, Equatable {
    public var name: String
    public var type: JointType
    public var parent: String
    public var child: String
    public var origin: Pose
    public var axis: SIMD3<Double>
    public var limit: JointLimit?

    public init(
        name: String,
        type: JointType,
        parent: String,
        child: String,
        origin: Pose = .identity,
        axis: SIMD3<Double> = SIMD3(0, 0, 1),
        limit: JointLimit? = nil
    ) {
        self.name = name
        self.type = type
        self.parent = parent
        self.child = child
        self.origin = origin
        self.axis = axis
        self.limit = limit
    }
}
