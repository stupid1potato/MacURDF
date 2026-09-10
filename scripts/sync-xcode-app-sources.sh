#!/usr/bin/env bash
# Sync repo MacURDFApp Sources into a local Xcode app copy (prevents drift from GitHub main).
#
# Detects layout:
#   flat:     DEST/AppModel.swift or DEST/MacURDFApp.swift  → rsync into DEST/
#   nested:   DEST/MacURDFApp/*.swift                      → rsync into DEST/MacURDFApp/
#   spm-like: DEST/Sources/MacURDFApp/                     → rsync into that
#
# Usage (typical local Xcode copy):
#   ./scripts/sync-xcode-app-sources.sh /Users/acb/MacURDF/MacURDFApp
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/MacURDFApp/Sources/MacURDFApp"
DEST="${1:-}"

usage() {
  echo "Usage: $0 /path/to/XcodeMacURDFAppSources" >&2
  echo "Example: $0 /Users/acb/MacURDF/MacURDFApp" >&2
  echo "  (flat folder that already contains AppModel.swift / Views / …)" >&2
}

if [[ -z "$DEST" ]]; then
  usage
  exit 1
fi
if [[ ! -d "$SRC" ]]; then
  echo "Missing sources: $SRC" >&2
  exit 1
fi
if [[ ! -d "$DEST" ]]; then
  echo "DEST does not exist: $DEST" >&2
  usage
  exit 1
fi

DEST="$(cd "$DEST" && pwd)"

is_app_sources_dir() {
  local d="$1"
  [[ -f "$d/AppModel.swift" || -f "$d/MacURDFApp.swift" ]]
}

TARGET=""
if is_app_sources_dir "$DEST"; then
  # Flat Xcode copy: .../MacURDFApp/*.swift
  TARGET="$DEST"
elif [[ -d "$DEST/MacURDFApp" ]] && is_app_sources_dir "$DEST/MacURDFApp"; then
  TARGET="$DEST/MacURDFApp"
elif [[ -d "$DEST/Sources/MacURDFApp" ]] && is_app_sources_dir "$DEST/Sources/MacURDFApp"; then
  TARGET="$DEST/Sources/MacURDFApp"
elif [[ -d "$DEST/Sources/MacURDFApp" ]]; then
  TARGET="$DEST/Sources/MacURDFApp"
else
  echo "Could not detect MacURDFApp sources under: $DEST" >&2
  echo "Expected flat AppModel.swift here, or MacURDFApp/, or Sources/MacURDFApp/." >&2
  echo "Do not pass the outer MacURDF/ folder unless it contains one of those layouts." >&2
  exit 1
fi

mkdir -p "$TARGET"
sync_tree() {
  local src="$1" dest="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.DS_Store' \
      --exclude '.git' \
      "$src/" "$dest/"
  else
    # Portable fallback (no rsync): mirror by clearing dest then cp
    find "$dest" -mindepth 1 -maxdepth 1 ! -name '.DS_Store' -exec rm -rf {} +
    cp -a "$src"/. "$dest"/
  fi
}
sync_tree "$SRC" "$TARGET"

# Entitlements next to common Resources locations
for RES in "$TARGET/../Resources" "$DEST/Resources" "$DEST/../Resources"; do
  if [[ -d "$RES" ]]; then
    cp -f "$ROOT/MacURDFApp/Resources/MacURDFApp.entitlements" "$RES/" 2>/dev/null || true
  fi
done

echo "Synced $SRC -> $TARGET"
echo "Prefer pointing the Xcode target at repo MacURDFApp/Sources/MacURDFApp instead of copying."
