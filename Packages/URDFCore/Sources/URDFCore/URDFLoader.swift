import Foundation

public struct URDFLoader: URDFLoading, Sendable {
    public init() {}

    public func load(urdfURL: URL) throws -> URDFDocument {
        let data: Data
        do {
            data = try Data(contentsOf: urdfURL)
        } catch {
            throw error
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        // Quick xacro sniff before parse (also caught by element handler).
        let lower = text.lowercased()
        let sniffsXacro = lower.contains("xmlns:xacro")
            || lower.contains("<xacro:")
            || urdfURL.pathExtension.lowercased() == "xacro"

        let parser = URDFXMLParser()
        parser.parse(data: data, sourceFile: urdfURL.lastPathComponent)

        if let fatal = parser.fatalParseError, parser.links.isEmpty && parser.joints.isEmpty {
            // Completely broken XML → throw
            throw fatal
        }

        var errors = parser.errors
        var warnings = parser.warnings
        if sniffsXacro {
            let already = errors.contains { $0.message.contains("xacro") }
            if !already {
                errors.append(
                    URDFIssue(
                        severity: .error,
                        file: urdfURL.lastPathComponent,
                        message: "xacro는 v0.1 미지원",
                        hint: "xacro를 urdf로 전처리하세요"
                    )
                )
            }
        }

        let name = parser.robotName.isEmpty ? urdfURL.deletingPathExtension().lastPathComponent : parser.robotName
        return URDFDocument(
            sourceURL: urdfURL,
            robotName: name,
            links: parser.links,
            joints: parser.joints,
            warnings: warnings,
            errors: errors
        )
    }
}
