import SwiftUI
import URDFCore

/// Real link/joint tree (Phase 2).
struct LinkTreeView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links / Joints")
                .font(.headline)

            if let doc = appModel.document {
                Text(doc.robotName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                List(selection: binding) {
                    Section("Links (\(doc.links.count))") {
                        ForEach(doc.links, id: \.name) { link in
                            Label(link.name, systemImage: "cube")
                                .tag(Selection.link(link.name))
                                .listRowBackground(
                                    appModel.selectedLinkName == link.name
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear
                                )
                        }
                    }
                    Section("Joints (\(doc.joints.count))") {
                        ForEach(doc.joints, id: \.name) { joint in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(joint.name, systemImage: "arrow.triangle.2.circlepath")
                                Text("\(joint.parent) → \(joint.child)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Selection.joint(joint.name))
                            .listRowBackground(
                                appModel.selectedJointName == joint.name
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                Text("Open a URDF to populate the tree.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(.thinMaterial)
    }

    private var binding: Binding<Selection?> {
        Binding(
            get: {
                if let j = appModel.selectedJointName { return .joint(j) }
                if let l = appModel.selectedLinkName { return .link(l) }
                return nil
            },
            set: { newValue in
                switch newValue {
                case .joint(let name):
                    appModel.selectJoint(name)
                case .link(let name):
                    appModel.selectJoint(nil)
                    appModel.selectLink(name)
                case .none:
                    appModel.selectJoint(nil)
                    appModel.selectLink(nil)
                }
            }
        )
    }

    private enum Selection: Hashable {
        case link(String)
        case joint(String)
    }
}
