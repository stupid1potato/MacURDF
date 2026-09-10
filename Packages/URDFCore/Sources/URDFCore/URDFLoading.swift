import Foundation

public protocol URDFLoading: Sendable {
    func load(urdfURL: URL) throws -> URDFDocument
}
