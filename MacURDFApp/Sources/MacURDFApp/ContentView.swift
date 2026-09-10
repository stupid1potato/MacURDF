import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                LinkTreeView()
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

                SceneViewportView()
                    .frame(minWidth: 400)

                JointSlidersView()
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 340)
            }
            .frame(maxHeight: .infinity)

            Divider()

            IssuesPanelPlaceholder(
                issues: appModel.displayedIssues,
                status: appModel.statusMessage
            )
            .frame(minHeight: 120, idealHeight: 160, maxHeight: 260)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
                    Task { @MainActor in
                        if isDir.boolValue {
                            appModel.loadFromFolder(url)
                        } else {
                            let ext = url.pathExtension.lowercased()
                            guard ext == "urdf" || ext == "xml" else { return }
                            appModel.load(url: url)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
