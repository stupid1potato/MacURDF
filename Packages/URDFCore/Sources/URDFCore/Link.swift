import Foundation

public struct Link: Sendable, Equatable {
    public var name: String
    public var visuals: [Visual]
    public var collisions: [Collision]

    public init(name: String, visuals: [Visual] = [], collisions: [Collision] = []) {
        self.name = name
        self.visuals = visuals
        self.collisions = collisions
    }
}
