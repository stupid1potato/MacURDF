import Foundation
import simd

enum TransformMath {
    /// URDF: T = trans(xyz) * R_z(yaw) * R_y(pitch) * R_x(roll)
    static func matrix(from pose: Pose) -> simd_float4x4 {
        let t = translation(pose.xyz)
        let rz = rotationZ(Float(pose.rpy.z))
        let ry = rotationY(Float(pose.rpy.y))
        let rx = rotationX(Float(pose.rpy.x))
        return t * rz * ry * rx
    }

    static func translation(_ xyz: SIMD3<Double>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(Float(xyz.x), Float(xyz.y), Float(xyz.z), 1)
        return m
    }

    static func rotationX(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func rotationY(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func rotationZ(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(
            SIMD4(c, s, 0, 0),
            SIMD4(-s, c, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    /// Rodrigues rotation around arbitrary axis.
    static func rotation(axis: SIMD3<Double>, angle: Double) -> simd_float4x4 {
        let len = simd_length(axis)
        guard len > 1e-12 else { return matrix_identity_float4x4 }
        let u = SIMD3<Float>(Float(axis.x / len), Float(axis.y / len), Float(axis.z / len))
        let a = Float(angle)
        let c = cos(a), s = sin(a)
        let t = 1 - c
        let x = u.x, y = u.y, z = u.z
        return simd_float4x4(
            SIMD4(t*x*x + c,     t*x*y + s*z, t*x*z - s*y, 0),
            SIMD4(t*x*y - s*z,   t*y*y + c,   t*y*z + s*x, 0),
            SIMD4(t*x*z + s*y,   t*y*z - s*x, t*z*z + c,   0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func translationAlong(axis: SIMD3<Double>, distance: Double) -> simd_float4x4 {
        let len = simd_length(axis)
        guard len > 1e-12 else { return matrix_identity_float4x4 }
        let u = axis / len
        return translation(u * distance)
    }

    static func position(_ m: simd_float4x4) -> SIMD3<Float> {
        SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }
}
