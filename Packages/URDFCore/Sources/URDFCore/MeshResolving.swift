import Foundation

public enum MeshResolution: Sendable {
    case resolved(URL)
    case missing(path: String, tried: [URL])
    case unsupported(ext: String, url: URL?)
}

public protocol MeshResolving: Sendable {
    func resolve(meshFilename: String, documentURL: URL, packageHints: [URL]) -> MeshResolution
}
