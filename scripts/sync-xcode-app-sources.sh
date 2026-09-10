#!/usr/bin/env bash
# Sync repo MacURDFApp Sources into a local Xcode app copy (prevents drift from GitHub main).
# Usage:
#   ./scripts/sync-xcode-app-sources.sh /Users/acb/MacURDF/MacURDF
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/MacURDFApp/Sources/MacURDFApp"
DEST="${1:-}"
if [[ -z "$DEST" ]]; then
  echo "Usage: $0 /path/to/XcodeAppCopyRoot" >&2
  echo "Example: $0 /Users/acb/MacURDF/MacURDF" >&2
  exit 1
fi
if [[ ! -d "$SRC" ]]; then
  echo "Missing sources: $SRC" >&2
  exit 1
fi
mkdir -p "$DEST"
rsync -a --delete \
  --exclude '.DS_Store' \
  "$SRC/" "$DEST/Sources/MacURDFApp/" 2>/dev/null \
  || rsync -a --delete --exclude '.DS_Store' "$SRC/" "$DEST/"
# Also copy entitlements next to Resources if present
if [[ -d "$DEST/../Resources" ]] || [[ -d "$DEST/Resources" ]]; then
  RES="$DEST/Resources"
  [[ -d "$DEST/../Resources" ]] && RES="$DEST/../Resources"
  mkdir -p "$RES"
  cp -f "$ROOT/MacURDFApp/Resources/MacURDFApp.entitlements" "$RES/" 2>/dev/null || true
fi
echo "Synced $SRC -> $DEST"
echo "Prefer pointing the Xcode target at ../MacURDFApp/Sources/MacURDFApp instead of copying."
