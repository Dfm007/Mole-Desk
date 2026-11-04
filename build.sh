#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
MOLE_SRC="$ROOT/Vendor/Mole"
APP="$ROOT/Mole Desk.app"
RUNTIME="$APP/Contents/Resources/Mole"

if [[ ! -x "$MOLE_SRC/mole" ]]; then
    echo "Vendored Mole runtime missing: $MOLE_SRC/mole" >&2
    exit 1
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -parse-as-library -swift-version 5 -O \
  -target x86_64-apple-macosx15.0 \
  "$ROOT/Sources/MoleDesk.swift" \
  -o "$APP/Contents/MacOS/MoleDesk" \
  -framework SwiftUI -framework AppKit -framework Charts
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/MoleIcon.icns" "$APP/Contents/Resources/MoleIcon.icns"
cp "$ROOT/Resources/MoleIcon.png" "$APP/Contents/Resources/MoleIcon.png"
mkdir -p "$APP/Contents/Resources/bin"
cp "$ROOT/Resources/bin/system_profiler" "$APP/Contents/Resources/bin/system_profiler"
chmod +x "$APP/Contents/Resources/bin/system_profiler"

# Self-contained Mole runtime. Only runtime files are copied; repository docs,
# tests, git metadata and development tooling stay outside the app bundle.
mkdir -p "$RUNTIME"
ditto "$MOLE_SRC/mole" "$RUNTIME/mole"
ditto "$MOLE_SRC/lib" "$RUNTIME/lib"
ditto "$MOLE_SRC/bin" "$RUNTIME/bin"
cp "$MOLE_SRC/LICENSE" "$RUNTIME/LICENSE"
cp "$MOLE_SRC/README_CN.md" "$RUNTIME/README_CN.md"

printf 'APPL????' > "$APP/Contents/PkgInfo"
"$RUNTIME/mole" --version >/dev/null
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
