import Foundation

public struct MeshAudit: Sendable {
    public var linkName: String
    public var filename: String
    public var resolution: MeshResolution

    public init(linkName: String, filename: String, resolution: MeshResolution) {
        self.linkName = linkName
        self.filename = filename
        self.resolution = resolution
    }
}

/// Audit all mesh geometries; also appends errors/warnings onto a copy of the document's issue lists if `mutatingDocument` provided.
public func auditMeshes(
    document: URDFDocument,
    resolver: MeshResolving,
    packageHints: [URL] = []
) -> [MeshAudit] {
    var audits: [MeshAudit] = []
    let docURL = document.sourceURL ?? URL(fileURLWithPath: "/")

    func consider(linkName: String, geometry: Geometry) {
        guard case let .mesh(filename, _) = geometry else { return }
        let resolution = resolver.resolve(
            meshFilename: filename,
            documentURL: docURL,
            packageHints: packageHints
        )
        audits.append(MeshAudit(linkName: linkName, filename: filename, resolution: resolution))
    }

    for link in document.links {
        for visual in link.visuals {
            consider(linkName: link.name, geometry: visual.geometry)
        }
        for collision in link.collisions {
            consider(linkName: link.name, geometry: collision.geometry)
        }
    }
    return audits
}

public extension URDFDocument {
    /// Returns a copy with mesh missing/unsupported reflected as issues.
    func applyingMeshAudit(
        resolver: MeshResolving,
        packageHints: [URL] = []
    ) -> (document: URDFDocument, audits: [MeshAudit]) {
        let audits = auditMeshes(document: self, resolver: resolver, packageHints: packageHints)
        var errors = self.errors
        var warnings = self.warnings

        for audit in audits {
            switch audit.resolution {
            case .resolved:
                break
            case let .missing(path, tried):
                let triedDesc = tried.map(\.path).joined(separator: ", ")
                errors.append(
                    URDFIssue(
                        severity: .error,
                        file: sourceURL?.lastPathComponent,
                        tag: "mesh",
                        message: "메시를 찾을 수 없습니다: \(path) (link: \(audit.linkName))",
                        hint: tried.isEmpty
                            ? "package:// 또는 meshes/ 경로를 확인하세요"
                            : "시도한 경로: \(triedDesc)"
                    )
                )
            case let .unsupported(ext, url):
                warnings.append(
                    URDFIssue(
                        severity: .warning,
                        file: sourceURL?.lastPathComponent,
                        tag: "mesh",
                        message: "지원하지 않는 메시 확장자 .\(ext) (link: \(audit.linkName))",
                        hint: url.map { "파일: \($0.path)" } ?? "stl/obj/dae만 지원"
                    )
                )
            }
        }

        var copy = self
        copy.errors = errors
        copy.warnings = warnings
        return (copy, audits)
    }
}
