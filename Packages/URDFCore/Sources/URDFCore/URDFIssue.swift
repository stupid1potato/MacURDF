import Foundation

public struct URDFIssue: Equatable, Sendable {
    public var severity: Severity
    public var file: String?
    public var line: Int?
    public var tag: String?
    public var message: String
    public var hint: String?

    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public init(
        severity: Severity,
        file: String? = nil,
        line: Int? = nil,
        tag: String? = nil,
        message: String,
        hint: String? = nil
    ) {
        self.severity = severity
        self.file = file
        self.line = line
        self.tag = tag
        self.message = message
        self.hint = hint
    }
}
