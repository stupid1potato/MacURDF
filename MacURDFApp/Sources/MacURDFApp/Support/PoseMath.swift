import Foundation
import simd
import URDFCore

/// App-local Pose → matrix (URDF ZYX). Core TransformMath is internal.
enum PoseMath {
    static func matrix(from pose: Pose) -> simd_float4x4 {
        let t = translation(pose.xyz)
        let rz = rotationZ(Float(pose.rpy.z))
        let ry = rotationY(Float(pose.rpy.y))
        let rx = rotationX(Float(pose.rpy.x))
        return t * rz * ry * rx
    }

    private static func translation(_ xyz: SIMD3<Double>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(Float(xyz.x), Float(xyz.y), Float(xyz.z), 1)
        return m
    }

    private static func rotationX(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    private static func rotationY(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    private static func rotationZ(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(
            SIMD4(c, s, 0, 0),
            SIMD4(-s, c, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        )
    }
}
