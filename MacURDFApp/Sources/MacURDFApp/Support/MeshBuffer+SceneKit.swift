import Foundation
import SceneKit
import simd
import URDFCore

enum MeshBufferSceneKit {
    /// Converts Core `MeshBuffer` → `SCNGeometry` (positions + indices + optional normals).
    static func geometry(from buffer: MeshBuffer) -> SCNGeometry {
        var positions = buffer.positions
        let positionData = Data(
            bytes: &positions,
            count: positions.count * MemoryLayout<SIMD3<Float>>.stride
        )
        let positionSource = SCNGeometrySource(
            data: positionData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        var sources: [SCNGeometrySource] = [positionSource]

        if var normals = buffer.normals, normals.count == positions.count {
            let normalData = Data(
                bytes: &normals,
                count: normals.count * MemoryLayout<SIMD3<Float>>.stride
            )
            sources.append(
                SCNGeometrySource(
                    data: normalData,
                    semantic: .normal,
                    vectorCount: normals.count,
                    usesFloatComponents: true,
                    componentsPerVector: 3,
                    bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0,
                    dataStride: MemoryLayout<SIMD3<Float>>.stride
                )
            )
        }

        var indices = buffer.indices
        let indexData = Data(
            bytes: &indices,
            count: indices.count * MemoryLayout<UInt32>.size
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geo = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.isDoubleSided = true
        geo.materials = [material]
        return geo
    }
}
