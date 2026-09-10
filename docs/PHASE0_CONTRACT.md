# MacURDF Phase 0 — Frozen contracts

App name: **MacURDF** (확정)
Root: `/workspace/macurdf`
Modules:
- `Packages/URDFCore` — 개발자2, UI 의존 0
- `MacURDFApp` — 개발자3, URDFCore만 의존

## Public API (동결)

```swift
public struct URDFIssue: Equatable, Sendable {
  public var severity: Severity // error | warning
  public var file: String?
  public var line: Int?
  public var tag: String?
  public var message: String
  public var hint: String?
  public enum Severity: String, Sendable { case error, warning }
}

public struct URDFDocument: Sendable {
  public var sourceURL: URL?
  public var robotName: String
  public var links: [Link]
  public var joints: [Joint]
  public var warnings: [URDFIssue]
  public var errors: [URDFIssue]
}

public struct JointState: Sendable {
  public var values: [String: Double] // jointName -> position (rad or m)
}

public protocol URDFLoading: Sendable {
  func load(urdfURL: URL) throws -> URDFDocument
}

public protocol Kinematics: Sendable {
  /// key = link name, value = world transform
  func transforms(document: URDFDocument, state: JointState) -> [String: simd_float4x4]
}

public enum MeshResolution: Sendable {
  case resolved(URL)
  case missing(path: String, tried: [URL])
  case unsupported(ext: String, url: URL?)
}

public protocol MeshResolving: Sendable {
  func resolve(meshFilename: String, documentURL: URL, packageHints: [URL]) -> MeshResolution
}
```

Link/Joint/Visual/Collision/Geometry 상세는 Phase 1에서 개발자2가 채우되 위 타입명 유지.

## Ownership

개발자2: Packages/URDFCore/**, fixtures/** (샘플 URDF)
개발자3: MacURDFApp/**, Xcode project / Package.swift app wiring
팀장: docs/**, 최종 SPM 의존 승인, GitHub 새 레포는 MVP 완료 후

## Phase plan

0 계약·스캐폴드
1 Core: 파서+이슈 / App: 셸+빈 SceneKit+Open
2 Core: package://·메시 resolve / App: 트리+에러패널
3 Core: FK+JointState / App: 슬라이더+visual/collision+Reload
4 통합 데모·README·GitHub 새 레포 푸시
