import SwiftUI
import URDFCore

/// Joint sliders for revolute / prismatic / continuous.
struct JointSlidersView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Joints")
                .font(.headline)

            if let doc = appModel.document {
                let movable = doc.joints.filter {
                    switch $0.type {
                    case .revolute, .prismatic, .continuous: return true
                    default: return false
                    }
                }
                if movable.isEmpty {
                    Text("No movable joints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(movable, id: \.name) { joint in
                        JointSliderRow(joint: joint)
                    }
                    .listStyle(.plain)
                }
            } else {
                Text("Open a URDF to edit joints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(.thinMaterial)
    }
}

private struct JointSliderRow: View {
    @EnvironmentObject private var appModel: AppModel
    let joint: Joint

    var body: some View {
        let range = sliderRange(for: joint)
        let value = Binding<Double>(
            get: { appModel.jointState.values[joint.name] ?? 0 },
            set: { appModel.setJoint(joint.name, value: $0) }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(joint.name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(joint.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .background(
            appModel.selectedJointName == joint.name
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture { appModel.selectJoint(joint.name) }
    }

    private func sliderRange(for joint: Joint) -> ClosedRange<Double> {
        switch joint.type {
        case .continuous:
            return (-Double.pi)...Double.pi
        case .revolute, .prismatic:
            if let limit = joint.limit, limit.lower < limit.upper {
                return limit.lower...limit.upper
            }
            return joint.type == .prismatic ? (-1)...1 : (-Double.pi)...Double.pi
        default:
            return (-1)...1
        }
    }
}
