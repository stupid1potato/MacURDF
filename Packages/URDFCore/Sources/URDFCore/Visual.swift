import Foundation

public struct Visual: Sendable, Equatable {
    public var origin: Pose
    public var geometry: Geometry
    public var materialName: String?

    public init(origin: Pose = .identity, geometry: Geometry, materialName: String? = nil) {
        self.origin = origin
        self.geometry = geometry
        self.materialName = materialName
    }
}
