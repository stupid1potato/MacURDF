import XCTest
@testable import URDFCore

final class URDFCoreTests: XCTestCase {
    func testURDFLoaderInstantiates() {
        XCTAssertNotNil(URDFLoader())
    }

    func testSimpleArmParses() throws {
        let url = fixtureURL("simple_arm/simple_arm.urdf")
        let doc = try URDFLoader().load(urdfURL: url)
        XCTAssertEqual(doc.robotName, "simple_arm")
        XCTAssertEqual(doc.links.count, 2)
        XCTAssertEqual(doc.joints.count, 1)
        XCTAssertTrue(doc.errors.isEmpty, "errors: \(doc.errors)")
    }

    func testBrokenXMLProducesErrorsOrThrow() {
        let url = fixtureURL("broken/broken.urdf")
        do {
            let doc = try URDFLoader().load(urdfURL: url)
            XCTAssertFalse(doc.errors.isEmpty)
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testPackageMeshResolved() throws {
        let url = fixtureURL("pkg_robot/urdf/pkg_robot.urdf")
        let doc = try URDFLoader().load(urdfURL: url)
        let resolver = LocalMeshResolver()
        let audits = auditMeshes(document: doc, resolver: resolver)

        let resolved = audits.first { audit in
            guard audit.linkName == "base" else { return false }
            if case .resolved = audit.resolution { return true }
            return false
        }
        XCTAssertNotNil(resolved, "package:// demo_pkg mesh should resolve: \(audits)")
    }

    func testPackageMeshMissing() throws {
        let url = fixtureURL("pkg_robot/urdf/pkg_robot.urdf")
        let doc = try URDFLoader().load(urdfURL: url)
        let resolver = LocalMeshResolver()
        let (audited, audits) = doc.applyingMeshAudit(resolver: resolver)
        let missing = audits.first { $0.linkName == "missing_link" }
        guard case .missing = missing?.resolution else {
            return XCTFail("expected missing for nope.stl: \(String(describing: missing))")
        }
        XCTAssertTrue(audited.errors.contains { $0.message.contains("nope.stl") })
    }

    func testRelativeMeshResolved() throws {
        let url = fixtureURL("pkg_robot/urdf/pkg_robot.urdf")
        let doc = try URDFLoader().load(urdfURL: url)
        let resolver = LocalMeshResolver()
        let audits = auditMeshes(document: doc, resolver: resolver)
        let relative = audits.first { $0.linkName == "relative_link" }
        guard case .resolved = relative?.resolution else {
            return XCTFail("relative mesh should resolve: \(String(describing: relative))")
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
