import Foundation
import simd

public protocol Kinematics: Sendable {
    /// key = link name, value = world transform
    func transforms(document: URDFDocument, state: JointState) -> [String: simd_float4x4]
}
