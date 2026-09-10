# MacURDFApp (Developer 3)

macOS 14+ SwiftUI + SceneKit shell. Depends on local SPM package `Packages/URDFCore`.

## Open flow (Phase 1)

1. **File > Open… (⌘O)** / **DnD `.urdf`** / **DocumentGroup** → `AppModel.load(url:)` → `URDFLoader().load`
2. On success: `document`, `jointState`, Issues from `errors`+`warnings`, status = robotName + counts
3. **Reload (⌘R)** re-runs load on `openedURL`
4. Folder drop deferred to Phase 2

## Open flow (Phase 0 archive)

1. **File > Open… (⌘O)** — `NSOpenPanel` filters `.urdf` / XML. Stores URL in `AppModel`; parse deferred to Phase 1 (`URDFLoading`).
2. **DocumentGroup** — `URDFFileDocument` registers `.urdf` UTI for document-based open (same deferral).
3. **File > Reload (⌘R)** — no-op + status TODO (Phase 1+).

## Layout

| Region | View | Phase |
|--------|------|-------|
| Leading | `LinkTreePlaceholder` | 2 |
| Center | `SceneViewportView` (grid, axes, orbit cam, placeholder cube) | 0 |
| Trailing | `JointSlidersPlaceholder` | 3 |
| Bottom | `IssuesPanelPlaceholder` | 2 |

## Build on a Mac (Xcode)

This Linux box has no Xcode. On macOS:

```bash
cd /path/to/macurdf
open Package.swift
```

Then either:
- Create an **App** target in Xcode that compiles `MacURDFApp/Sources/MacURDFApp` and links product `URDFCore`, using `MacURDFApp/Resources/Info.plist` document types, or
- Use `swift build` to compile the library target `MacURDFApp` (UI `@main` needs an App target to run).

## Dependency

```swift
.package(path: "Packages/URDFCore")
```

Do not add CocoaPods / Electron / unapproved libraries.

## Phase 2 — packageHints rules

On every file load, hints accumulate:
1. URDF file's parent directory
2. That directory's parent (common `urdf/` + `meshes/` layout)
3. Any folder dropped onto the window (`loadFromFolder`)

`LocalMeshResolver` + `document.applyingMeshAudit(resolver:packageHints:)` runs after parse; Issues show missing/unsupported meshes.

### Folder DnD
- 0 `.urdf` → error issue
- 1 `.urdf` → load it + add folder to hints
- N `.urdf` → load first (sorted path) + warning issue

### Scene (no FK)
- Primitive geometries → SCNBox/Cylinder/Sphere
- Mesh missing → red box; mesh resolved → yellow box (STL Phase 3)
- All link nodes at identity


## Source of truth (anti-drift)

**Canonical app sources:** `MacURDFApp/Sources/MacURDFApp` in this repo (GitHub `main`).

If you keep a separate Xcode app folder (e.g. `/Users/…/MacURDF/MacURDFApp` with flat `.swift` sources), either:

1. **Preferred:** Point the App target’s Compile Sources at `../MacURDFApp/Sources/MacURDFApp` (and link local `Packages/URDFCore`), commit the `.xcodeproj` into the repo when ready; or
2. **Temporary:** After `git pull`, run `./scripts/sync-xcode-app-sources.sh /Users/acb/MacURDF/MacURDFApp`.

Attach `MacURDFApp/Resources/MacURDFApp.entitlements` to the App target (`App Sandbox` + `User Selected File` Read Only + bookmarks). Without user-selected file access, DAE under `package://…` often fails as yellow placeholders.

## Phase 3+ viewport

- Joint slider changes update **link `simdTransform` in place** (no SCNView/`sceneEpoch` rebuild).
- `sceneEpoch` bumps only on open/reload, visual/collision toggle, and selection halo changes.
