import SwiftUI
import URDFCore
import UniformTypeIdentifiers

@main
struct MacURDFApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Open…") {
                    appModel.openURDF()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reload") {
                    appModel.reload()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("View") {
                Toggle(
                    "Visual",
                    isOn: Binding(
                        get: { appModel.showVisual },
                        set: { appModel.setShowVisual($0) }
                    )
                )
                Toggle(
                    "Collision",
                    isOn: Binding(
                        get: { appModel.showCollision },
                        set: { appModel.setShowCollision($0) }
                    )
                )
            }
        }

        DocumentGroup(viewing: URDFFileDocument.self) { file in
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    appModel.noteOpenedDocument(url: file.fileURL)
                }
                .frame(minWidth: 1100, minHeight: 700)
        }
    }
}

extension UTType {
    static var urdf: UTType {
        UTType(filenameExtension: "urdf")
            ?? UTType(importedAs: "org.ros.urdf")
    }
}
