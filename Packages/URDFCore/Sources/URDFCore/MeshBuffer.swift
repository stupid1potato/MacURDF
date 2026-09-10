import Foundation
import simd

public struct MeshBuffer: Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]?
    public var indices: [UInt32]

    public init(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        indices: [UInt32]
    ) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }
}

public enum MeshLoadError: Error, Equatable, Sendable {
    case unsupported
    case decodeFailed(String)
}

public protocol MeshLoading: Sendable {
    func load(url: URL) throws -> MeshBuffer
}
