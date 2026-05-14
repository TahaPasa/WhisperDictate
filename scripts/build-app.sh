#!/usr/bin/env bash
# Builds WhisperDictate.app in dist/ from source.
# Usage: bash scripts/build-app.sh [--arch arm64|x86_64|universal]
#
# Steps:
#   0. Generate AppIcon.icns (skipped if already present)
#   1. Build whisper-cli (idempotent)
#   2. Copy whisper-cli into Resources/bin/
#   3. swift build -c release
#   4. Assemble .app bundle
#   5. Ad-hoc codesign so TCC can attach permissions to the bundle ID
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$REPO_ROOT/dist"
APP="$DIST/WhisperDictate.app"
CONTENTS="$APP/Contents"

ARCH="${1:-arm64}"

# ── 0. Generate app icon ───────────────────────────────────────────────────
if [[ ! -f "$REPO_ROOT/Resources/AppIcon.icns" ]]; then
    echo "==> [0/5] Generating AppIcon.icns…"
    swift "$REPO_ROOT/scripts/generate-icon.swift"
else
    echo "==> [0/5] AppIcon.icns already present (delete to regenerate)"
fi

# ── 1. Build whisper-cli ────────────────────────────────────────────────────
echo "==> [1/5] Ensuring whisper-cli is built…"
bash "$REPO_ROOT/scripts/build-whisper.sh"

# ── 2. Stage whisper-cli into Resources/bin/ ────────────────────────────────
echo "==> [2/5] Staging whisper-cli into Resources/bin/…"
mkdir -p "$REPO_ROOT/Resources/bin"
cp -f "$REPO_ROOT/whisper.cpp/build/bin/whisper-cli" "$REPO_ROOT/Resources/bin/whisper-cli"

# ── 3. swift build ──────────────────────────────────────────────────────────
echo "==> [3/5] Building Swift package (release, $ARCH)…"
cd "$REPO_ROOT"
if [[ "$ARCH" == "universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BINARY=".build/apple/Products/Release/WhisperDictate"
else
    swift build -c release --arch "$ARCH"
    BINARY=".build/$ARCH-apple-macosx/release/WhisperDictate"
fi

# ── 4. Assemble .app bundle ─────────────────────────────────────────────────
echo "==> [4/5] Assembling .app bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/bin"

# Executable
cp -f "$REPO_ROOT/$BINARY" "$CONTENTS/MacOS/WhisperDictate"

# whisper-cli subprocess binary
cp -f "$REPO_ROOT/Resources/bin/whisper-cli" "$CONTENTS/Resources/bin/whisper-cli"

# Info.plist (copy template directly — no substitution needed)
cp -f "$REPO_ROOT/Resources/Info.plist.template" "$CONTENTS/Info.plist"

# Optional app icon
if [[ -f "$REPO_ROOT/Resources/AppIcon.icns" ]]; then
    cp -f "$REPO_ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

echo "    Bundle: $APP"

# ── 5. Ad-hoc codesign ──────────────────────────────────────────────────────
echo "==> [5/5] Ad-hoc codesigning (--sign -)…"
# Sign the subprocess first, then the outer bundle.
codesign --force --sign - "$CONTENTS/Resources/bin/whisper-cli"
codesign --force --deep --sign - "$APP"

echo ""
echo "✓ Build complete: $APP"
echo ""
echo "To launch:"
echo "  open \"$APP\""
echo ""
echo "First-run checklist:"
echo "  1. System Settings → Keyboard → Shortcuts → Launchpad & Dock → uncheck 'Turn Dock Hiding On/Off' (frees ⌘⌥D)"
echo "  2. Click the mic icon in the menu bar → Model → Download Base (multilingual, ~142 MB) or any other model"
echo "  3. Press ⌘⌥D to start dictating; press ⌘⌥D again to stop and copy to clipboard"
