# MacURDF

Native macOS URDF viewer (ROS not required). Open a `.urdf`, inspect the link tree, scrub joints, and see visual/collision geometry in SceneKit.

**Requires:** macOS 14+, Apple Silicon preferred (Intel best-effort), Xcode 15+.

## Modules

| Module | Owner | Role |
|--------|-------|------|
| `Packages/URDFCore` | 개발자2 | Parse, `package://` resolve, FK, mesh buffers (STL/OBJ) |
| `MacURDFApp` | 개발자3 | SwiftUI shell, SceneKit viewport, joint sliders, DnD |

SPM only. No CocoaPods, Electron, Python, or ROS runtime.

## MVP (v0.1)

- Open / Reload (⌘R) / drag-and-drop file or folder
- Parse robot, link, joint, visual, collision, primitives + mesh
- `package://` and relative `meshes/` resolution with issue list
- Orbit camera, grid, world axes
- Link/joint tree + revolute/prismatic/continuous sliders (limits)
- Visual / Collision toggles
- Error/warning panel (file, line/tag, hint)
- STL (ASCII/binary) + OBJ mesh display; DAE → placeholder + warning

## Fixtures

- `fixtures/simple_arm/` — boxes only
- `fixtures/simple_arm_mesh/` — relative `meshes/link.stl`
- `fixtures/pkg_robot/` — `package://demo_pkg/...`
- `fixtures/broken/` — malformed XML

## Build (Mac)

```bash
cd macurdf
open Package.swift
```

Create a macOS **App** target that compiles `MacURDFApp/Sources/MacURDFApp`, links product `URDFCore`, and uses `MacURDFApp/Resources/Info.plist` document types. Then Run.

```bash
cd Packages/URDFCore && swift test
```

## Limitations (honest)

- **xacro** not supported in v0.1 (clear error + hint)
- **DAE/Collada** not loaded (unsupported placeholder)
- Floating/planar joints treated as fixed (+ warning)
- No physics, ROS topics, or WYSIWYG URDF editing
- Linux CI box cannot run the app (no Xcode); validate on a Mac

## License

TBD by repo owner.
