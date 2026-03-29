#!/usr/bin/env bash
# Builds PostureReminder.app (Release, no App Store signing).
# The result is placed in build/Release/ and optionally copied to /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Regenerate Xcode project ──────────────────────────────────────────────────
if command -v xcodegen &> /dev/null; then
    echo "→ xcodegen generate…"
    xcodegen generate --quiet
else
    echo "⚠️  xcodegen not found — using existing .xcodeproj"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "→ Building Release…"
xcodebuild \
    -project PostureReminder.xcodeproj \
    -scheme  PostureReminder \
    -configuration Release \
    -derivedDataPath "$ROOT/build" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    | grep -E "^(Build|error:|warning:|✓|→)" || true

APP="$ROOT/build/Build/Products/Release/PostureReminder.app"

if [ ! -d "$APP" ]; then
    echo "❌  Build failed — check Xcode output above."
    exit 1
fi

echo ""
echo "✓ Build succeeded:"
echo "  $APP"
echo ""

# ── Optional: install to /Applications ───────────────────────────────────────
read -rp "Copy to /Applications? [y/N] " yn
if [[ "${yn:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "/Applications/PostureReminder.app"
    cp -r "$APP" /Applications/
    echo "✓ Installed → /Applications/PostureReminder.app"
fi
