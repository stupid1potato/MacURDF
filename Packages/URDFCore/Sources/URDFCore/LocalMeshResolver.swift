import Foundation

public struct LocalMeshResolver: MeshResolving, Sendable {
    public init() {}

    private static let supportedExt: Set<String> = ["stl", "obj", "dae"]

    public func resolve(
        meshFilename: String,
        documentURL: URL,
        packageHints: [URL]
    ) -> MeshResolution {
        let trimmed = meshFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .missing(path: meshFilename, tried: [])
        }

        var tried: [URL] = []
        let candidates = candidateURLs(
            filename: trimmed,
            documentURL: documentURL,
            packageHints: packageHints,
            tried: &tried
        )

        for url in candidates {
            let ext = url.pathExtension.lowercased()
            if FileManager.default.fileExists(atPath: url.path) {
                if Self.supportedExt.contains(ext) {
                    return .resolved(url)
                }
                return .unsupported(ext: ext.isEmpty ? "(none)" : ext, url: url)
            }
        }

        // If we never saw a supported extension in candidates but path exists nowhere:
        let ext = (trimmed as NSString).pathExtension.lowercased()
        if !ext.isEmpty && !Self.supportedExt.contains(ext) {
            // Absolute-like unsupported reference with no file
            return .unsupported(ext: ext, url: nil)
        }
        return .missing(path: trimmed, tried: tried)
    }

    private func candidateURLs(
        filename: String,
        documentURL: URL,
        packageHints: [URL],
        tried: inout [URL]
    ) -> [URL] {
        var urls: [URL] = []
        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            if !urls.contains(standardized) {
                urls.append(standardized)
                tried.append(standardized)
            }
        }

        let docDir = documentURL.deletingLastPathComponent()

        if filename.hasPrefix("package://") {
            let rest = String(filename.dropFirst("package://".count))
            let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let pkg = String(parts.first ?? "")
            let remainder = parts.count > 1 ? String(parts[1]) : ""

            // Search upward from document for PKG folder
            var dir = docDir
            for _ in 0..<12 {
                let pkgRoot = dir.appendingPathComponent(pkg, isDirectory: true)
                if remainder.isEmpty {
                    add(pkgRoot)
                } else {
                    add(pkgRoot.appendingPathComponent(remainder))
                }
                // Also try PKG/rest when rest already includes meshes/...
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }

            for hint in packageHints {
                let base = hint.appendingPathComponent(pkg, isDirectory: true)
                if remainder.isEmpty {
                    add(base)
                } else {
                    add(base.appendingPathComponent(remainder))
                }
                // hint may already be the package root
                if remainder.isEmpty {
                    add(hint)
                } else {
                    add(hint.appendingPathComponent(remainder))
                }
            }
            return urls
        }

        // Absolute filesystem path
        if filename.hasPrefix("/") {
            add(URL(fileURLWithPath: filename))
            return urls
        }

        // Relative paths
        add(docDir.appendingPathComponent(filename))
        add(docDir.appendingPathComponent("meshes").appendingPathComponent((filename as NSString).lastPathComponent))
        add(docDir.appendingPathComponent("../meshes/\((filename as NSString).lastPathComponent)"))
        add(docDir.appendingPathComponent(filename).standardizedFileURL)
        // filename as-is relative to cwd (rare)
        add(URL(fileURLWithPath: filename))
        return urls
    }
}
