#!/usr/bin/env bash
# Generates all icon sizes and writes Assets.xcassets/AppIcon.appiconset/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/scripts/AppIcon_1024.png"
ICONSET="$ROOT/PostureReminder/Assets.xcassets/AppIcon.appiconset"

echo "→ Generating master icon…"
swift "$ROOT/scripts/make_icon.swift" "$MASTER"

echo "→ Resizing to all required sizes…"
mkdir -p "$ICONSET"

for SIZE in 16 32 64 128 256 512 1024; do
    OUT="$ICONSET/icon_${SIZE}.png"
    sips -z "$SIZE" "$SIZE" "$MASTER" --out "$OUT" > /dev/null
    echo "   ${SIZE}×${SIZE} → $(basename "$OUT")"
done

echo "→ Writing Contents.json…"
cat > "$ICONSET/Contents.json" << 'JSON'
{
  "images": [
    {"idiom":"mac","scale":"1x","size":"16x16",   "filename":"icon_16.png"},
    {"idiom":"mac","scale":"2x","size":"16x16",   "filename":"icon_32.png"},
    {"idiom":"mac","scale":"1x","size":"32x32",   "filename":"icon_32.png"},
    {"idiom":"mac","scale":"2x","size":"32x32",   "filename":"icon_64.png"},
    {"idiom":"mac","scale":"1x","size":"128x128", "filename":"icon_128.png"},
    {"idiom":"mac","scale":"2x","size":"128x128", "filename":"icon_256.png"},
    {"idiom":"mac","scale":"1x","size":"256x256", "filename":"icon_256.png"},
    {"idiom":"mac","scale":"2x","size":"256x256", "filename":"icon_512.png"},
    {"idiom":"mac","scale":"1x","size":"512x512", "filename":"icon_512.png"},
    {"idiom":"mac","scale":"2x","size":"512x512", "filename":"icon_1024.png"}
  ],
  "info": {"author":"xcode","version":1}
}
JSON

echo "✓ AppIcon.appiconset ready at:"
echo "  $ICONSET"
