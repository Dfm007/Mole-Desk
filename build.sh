#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
MOLE_SRC="$ROOT/Vendor/Mole"
APP="$ROOT/Mole Desk.app"
RUNTIME="$APP/Contents/Resources/Mole"
BUILD_DIR="$ROOT/build"
RUNTIME_STAMP="$BUILD_DIR/mole-runtime.sha256"

REQUIRED_GO_VERSION="$(awk '$1 == "toolchain" { print $2; exit }' "$MOLE_SRC/go.mod")"
if [[ -z "$REQUIRED_GO_VERSION" ]]; then
    REQUIRED_GO_VERSION="go$(awk '$1 == "go" { print $2; exit }' "$MOLE_SRC/go.mod")"
fi

mkdir -p "$BUILD_DIR"

if [[ ! -x "$MOLE_SRC/mole" ]]; then
    echo "Vendored Mole runtime missing: $MOLE_SRC/mole" >&2
    exit 1
fi

resolve_go() {
    if [[ -n "${MOLE_GO:-}" ]]; then
        if ! command -v "$MOLE_GO" >/dev/null 2>&1; then
            echo "MOLE_GO is not executable: $MOLE_GO" >&2
            return 1
        fi
        command -v "$MOLE_GO"
        return 0
    fi

    if command -v go >/dev/null 2>&1; then
        command -v go
        return 0
    fi

    local version="${REQUIRED_GO_VERSION#go}"
    local toolchain_dir="$BUILD_DIR/toolchain/$version"
    local go_bin="$toolchain_dir/go/bin/go"
    if [[ ! -x "$go_bin" ]]; then
        local host_arch
        case "$(uname -m)" in
            arm64) host_arch="arm64" ;;
            *) host_arch="amd64" ;;
        esac
        local archive="$BUILD_DIR/toolchain/$version.tar.gz"
        mkdir -p "$BUILD_DIR/toolchain" "$toolchain_dir"
        echo "Downloading $REQUIRED_GO_VERSION toolchain..." >&2
        curl -L --fail --retry 3 \
            "https://go.dev/dl/$REQUIRED_GO_VERSION.darwin-$host_arch.tar.gz" \
            -o "$archive" >&2
        tar -xzf "$archive" -C "$toolchain_dir"
    fi
    printf '%s\n' "$go_bin"
}

mole_runtime_fingerprint() {
    {
        printf 'toolchain=%s\n' "$REQUIRED_GO_VERSION"
        shasum -a 256 "$MOLE_SRC/go.mod" "$MOLE_SRC/go.sum"
        find "$MOLE_SRC/cmd" "$MOLE_SRC/internal" -type f -name '*.go' -print |
            LC_ALL=C sort |
            while IFS= read -r file; do
                shasum -a 256 "$file"
            done
    } | shasum -a 256 | awk '{print $1}'
}

has_arch() {
    lipo -archs "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"
}

runtime_is_current=false
runtime_fingerprint="$(mole_runtime_fingerprint)"
if [[ -f "$RUNTIME_STAMP" ]] && [[ "$(<"$RUNTIME_STAMP")" == "$runtime_fingerprint" ]]; then
    runtime_is_current=true
    for tool in status-go analyze-go; do
        binary="$MOLE_SRC/bin/$tool"
        if [[ ! -x "$binary" ]] || ! has_arch "$binary" x86_64 || ! has_arch "$binary" arm64; then
            runtime_is_current=false
        fi
    done
fi

if [[ "$runtime_is_current" != true ]]; then
    GO_BIN="$(resolve_go)"
    echo "Rebuilding Mole universal runtime from Vendor/Mole..." >&2
    mkdir -p \
        "$BUILD_DIR/mole-runtime/x86_64" \
        "$BUILD_DIR/mole-runtime/arm64"
    for arch in x86_64 arm64; do
        case "$arch" in
            x86_64) goarch="amd64" ;;
            arm64) goarch="arm64" ;;
        esac
        (
            cd "$MOLE_SRC"
            CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" "$GO_BIN" build \
                -trimpath -ldflags='-s -w' \
                -o "$BUILD_DIR/mole-runtime/$arch/analyze-go" ./cmd/analyze
            CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" "$GO_BIN" build \
                -trimpath -ldflags='-s -w' \
                -o "$BUILD_DIR/mole-runtime/$arch/status-go" ./cmd/status
        ) || exit 1
    done
    for tool in status-go analyze-go; do
        lipo -create \
            "$BUILD_DIR/mole-runtime/x86_64/$tool" \
            "$BUILD_DIR/mole-runtime/arm64/$tool" \
            -output "$BUILD_DIR/mole-runtime/$tool"
        cp "$BUILD_DIR/mole-runtime/$tool" "$MOLE_SRC/bin/$tool"
        chmod +x "$MOLE_SRC/bin/$tool"
    done
    printf '%s\n' "$runtime_fingerprint" > "$RUNTIME_STAMP"
else
    echo "Mole runtime is up to date." >&2
fi

for tool in status-go analyze-go; do
    if [[ ! -x "$MOLE_SRC/bin/$tool" ]]; then
        echo "Vendored Mole runtime missing: $MOLE_SRC/bin/$tool" >&2
        exit 1
    fi
    for arch in x86_64 arm64; do
        if ! has_arch "$MOLE_SRC/bin/$tool" "$arch"; then
            echo "Vendored $tool does not contain the $arch slice required for a universal build" >&2
            exit 1
        fi
    done
done

MOLE_ROOT="$MOLE_SRC" "$ROOT/Resources/bin/mole-uninstall-fast" --check-api >/dev/null

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
source_files=("$ROOT"/Sources/*.swift)
if [[ ${#source_files[@]} -eq 0 ]]; then
    echo "No Swift sources found in $ROOT/Sources" >&2
    exit 1
fi
xcrun swiftc -parse-as-library -swift-version 5 -O \
  -target x86_64-apple-macosx15.0 \
  "${source_files[@]}" \
  -o "$BUILD_DIR/MoleDesk-x86_64" \
  -framework SwiftUI -framework AppKit -framework Charts
xcrun swiftc -parse-as-library -swift-version 5 -O \
  -target arm64-apple-macosx15.0 \
  "${source_files[@]}" \
  -o "$BUILD_DIR/MoleDesk-arm64" \
  -framework SwiftUI -framework AppKit -framework Charts
lipo -create \
  "$BUILD_DIR/MoleDesk-x86_64" \
  "$BUILD_DIR/MoleDesk-arm64" \
  -output "$APP/Contents/MacOS/MoleDesk"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/MoleIcon.icns" "$APP/Contents/Resources/MoleIcon.icns"
cp "$ROOT/Resources/MoleIcon.png" "$APP/Contents/Resources/MoleIcon.png"
mkdir -p "$APP/Contents/Resources/bin"
cp "$ROOT/Resources/bin/system_profiler" "$APP/Contents/Resources/bin/system_profiler"
cp "$ROOT/Resources/bin/mole-askpass" "$APP/Contents/Resources/bin/mole-askpass"
cp "$ROOT/Resources/bin/mole-uninstall-fast" "$APP/Contents/Resources/bin/mole-uninstall-fast"
chmod +x \
    "$APP/Contents/Resources/bin/system_profiler" \
    "$APP/Contents/Resources/bin/mole-askpass" \
    "$APP/Contents/Resources/bin/mole-uninstall-fast"

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
