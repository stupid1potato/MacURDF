import SwiftUI
import UniformTypeIdentifiers

/// Phase 0 document shell for `.urdf` UTI. Parsing arrives in Phase 1 via URDFCore.
struct URDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.urdf, .xml] }
    static var writableContentTypes: [UTType] { [.urdf] }

    var rawText: String

    init(rawText: String = "") {
        self.rawText = rawText
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            rawText = text
        } else {
            rawText = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = rawText.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}
