import Foundation
import simd

public struct ForwardKinematics: Kinematics, Sendable {
    public init() {}

    public func transforms(
        document: URDFDocument,
        state: JointState
    ) -> [String: simd_float4x4] {
        var result: [String: simd_float4x4] = [:]
        var warnings: [String] = []

        let linkNames = Set(document.links.map(\.name))
        let childToJoint: [String: Joint] = Dictionary(
            uniqueKeysWithValues: document.joints.map { ($0.child, $0) }
        )
        let childrenByParent: [String: [Joint]] = Dictionary(grouping: document.joints, by: \.parent)

        // Roots: links that are never a child
        let childNames = Set(document.joints.map(\.child))
        let roots = document.links.map(\.name).filter { !childNames.contains($0) }

        if roots.isEmpty, let first = document.links.first {
            // Fallback: treat first link as root
            result[first.name] = matrix_identity_float4x4
            propagate(
                parent: first.name,
                parentT: matrix_identity_float4x4,
                childrenByParent: childrenByParent,
                linkNames: linkNames,
                state: state,
                result: &result,
                visiting: [],
                warnings: &warnings
            )
        } else {
            for root in roots {
                result[root] = matrix_identity_float4x4
                propagate(
                    parent: root,
                    parentT: matrix_identity_float4x4,
                    childrenByParent: childrenByParent,
                    linkNames: linkNames,
                    state: state,
                    result: &result,
                    visiting: [],
                    warnings: &warnings
                )
            }
        }

        // Orphan children (parent missing)
        for joint in document.joints {
            if result[joint.child] == nil {
                if !linkNames.contains(joint.parent) || result[joint.parent] == nil {
                    warnings.append("고아 joint \(joint.name): parent \(joint.parent) unreachable")
                }
            }
        }

        _ = warnings // consumers may later expose; Phase 3 DoD is transforms map
        _ = childToJoint
        return result
    }

    private func propagate(
        parent: String,
        parentT: simd_float4x4,
        childrenByParent: [String: [Joint]],
        linkNames: Set<String>,
        state: JointState,
        result: inout [String: simd_float4x4],
        visiting: [String],
        warnings: inout [String]
    ) {
        if visiting.contains(parent) {
            warnings.append("사이클 감지 near \(parent)")
            return
        }
        let nextVisiting = visiting + [parent]
        guard let joints = childrenByParent[parent] else { return }

        for joint in joints {
            guard linkNames.contains(joint.child) else {
                warnings.append("고아 child \(joint.child) in joint \(joint.name)")
                continue
            }
            if result[joint.child] != nil {
                // already assigned — cycle / multi-parent
                warnings.append("사이클 또는 중복 parent: \(joint.child)")
                continue
            }

            let originT = TransformMath.matrix(from: joint.origin)
            let motionT = jointMotion(joint: joint, state: state, warnings: &warnings)
            let childT = parentT * originT * motionT
            result[joint.child] = childT

            propagate(
                parent: joint.child,
                parentT: childT,
                childrenByParent: childrenByParent,
                linkNames: linkNames,
                state: state,
                result: &result,
                visiting: nextVisiting,
                warnings: &warnings
            )
        }
    }

    private func jointMotion(
        joint: Joint,
        state: JointState,
        warnings: inout [String]
    ) -> simd_float4x4 {
        var q = state.values[joint.name] ?? 0
        switch joint.type {
        case .revolute:
            if let limit = joint.limit {
                q = min(max(q, limit.lower), limit.upper)
            }
            return TransformMath.rotation(axis: joint.axis, angle: q)
        case .continuous:
            return TransformMath.rotation(axis: joint.axis, angle: q)
        case .prismatic:
            if let limit = joint.limit {
                q = min(max(q, limit.lower), limit.upper)
            }
            return TransformMath.translationAlong(axis: joint.axis, distance: q)
        case .fixed:
            return matrix_identity_float4x4
        case .floating, .planar:
            warnings.append("joint \(joint.name) type \(joint.type.rawValue)는 v0.1에서 I로 처리")
            return matrix_identity_float4x4
        }
    }
}
