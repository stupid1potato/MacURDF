import XCTest
@testable import URDFCore

final class MeshLoaderTests: XCTestCase {
    func testASCIISTLLoadsPositions() throws {
        let url = fixtureURL("pkg_robot/demo_pkg/meshes/box.stl")
        let buffer = try MeshLoader().load(url: url)
        XCTAssertFalse(buffer.positions.isEmpty)
        XCTAssertEqual(buffer.indices.count % 3, 0)
        XCTAssertNotNil(buffer.normals)
    }

    func testDAEUnsupported() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("x.dae")
        try? Data().write(to: tmp)
        XCTAssertThrowsError(try MeshLoader().load(url: tmp)) { error in
            XCTAssertEqual(error as? MeshLoadError, .unsupported)
        }
    }

    private func fixtureURL(_ relative: String) -> URL {
        let candidates: [URL] = [
            URL(fileURLWithPath: "/workspace/macurdf/fixtures/\(relative)"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("fixtures/\(relative)"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return candidates[0]
    }
}
