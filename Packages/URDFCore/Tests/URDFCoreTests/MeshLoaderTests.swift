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
        // #file → …/Tests/URDFCoreTests/*.swift
        // 5번 up → repo root (…/MacURDF)
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let fixture = url.appendingPathComponent("fixtures").appendingPathComponent(relative)
        precondition(
            FileManager.default.fileExists(atPath: fixture.path),
            "fixture missing: \(fixture.path)"
        )
        return fixture
    }
}
