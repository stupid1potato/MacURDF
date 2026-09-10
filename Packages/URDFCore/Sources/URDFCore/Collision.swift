import Foundation

public struct Collision: Sendable, Equatable {
    public var origin: Pose
    public var geometry: Geometry

    public init(origin: Pose = .identity, geometry: Geometry) {
        self.origin = origin
        self.geometry = geometry
    }
}
