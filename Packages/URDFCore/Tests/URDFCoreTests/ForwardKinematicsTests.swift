import XCTest
import simd
@testable import URDFCore

final class ForwardKinematicsTests: XCTestCase {
    func testSimpleArmZeroJoint() throws {
        let url = fixtureURL("simple_arm/simple_arm.urdf")
        let doc = try URDFLoader().load(urdfURL: url)
        let fk = ForwardKinematics()
        let state = JointState.zero(for: doc)
        let ts = fk.transforms(document: doc, state: state)

        XCTAssertNotNil(ts["base_link"])
        XCTAssertNotNil(ts["link1"])

        let link1 = try XCTUnwrap(ts["link1"])
        let p = SIMD3<Float>(link1.columns.3.x, link1.columns.3.y, link1.columns.3.z)
        // origin xyz="0 0 0.05" + joint1=0 → child roughly at z=0.05
        XCTAssertEqual(p.x, 0, accuracy: 1e-4)
        XCTAssertEqual(p.y, 0, accuracy: 1e-4)
        XCTAssertEqual(p.z, 0.05, accuracy: 1e-3)
    }

    func testSimpleArmHalfPi() throws {
        let url = fixtureURL("simple_arm/simple_arm.urdf")
        let doc = try URDFLoader().load(urdfURL: url)
        let fk = ForwardKinematics()
        var state = JointState.zero(for: doc)
        state.values["joint1"] = Double.pi / 2
        let ts = fk.transforms(document: doc, state: state)
        let link1 = try XCTUnwrap(ts["link1"])
        let p = SIMD3<Float>(link1.columns.3.x, link1.columns.3.y, link1.columns.3.z)
        // revolute about z at origin offset z=0.05: position stays ~ (0,0,0.05)
        XCTAssertEqual(p.z, 0.05, accuracy: 1e-3)
        // rotation about z by 90° — basis X should map toward +Y
        let xAxis = SIMD3<Float>(link1.columns.0.x, link1.columns.0.y, link1.columns.0.z)
        XCTAssertEqual(xAxis.x, 0, accuracy: 1e-3)
        XCTAssertEqual(xAxis.y, 1, accuracy: 1e-3)
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
