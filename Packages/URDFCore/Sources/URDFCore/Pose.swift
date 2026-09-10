import Foundation
import simd

public struct Pose: Sendable, Equatable {
    public var xyz: SIMD3<Double>
    public var rpy: SIMD3<Double>

    public init(xyz: SIMD3<Double> = .zero, rpy: SIMD3<Double> = .zero) {
        self.xyz = xyz
        self.rpy = rpy
    }

    public static let identity = Pose()
}
