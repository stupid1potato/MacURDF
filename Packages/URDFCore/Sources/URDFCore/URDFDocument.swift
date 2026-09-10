import Foundation

public struct URDFDocument: Sendable {
    public var sourceURL: URL?
    public var robotName: String
    public var links: [Link]
    public var joints: [Joint]
    public var warnings: [URDFIssue]
    public var errors: [URDFIssue]

    public init(
        sourceURL: URL? = nil,
        robotName: String,
        links: [Link] = [],
        joints: [Joint] = [],
        warnings: [URDFIssue] = [],
        errors: [URDFIssue] = []
    ) {
        self.sourceURL = sourceURL
        self.robotName = robotName
        self.links = links
        self.joints = joints
        self.warnings = warnings
        self.errors = errors
    }
}
