import Foundation
import simd

public enum Geometry: Sendable, Equatable {
    case box(size: SIMD3<Double>)
    case cylinder(radius: Double, length: Double)
    case sphere(radius: Double)
    case mesh(filename: String, scale: SIMD3<Double>?)
}
