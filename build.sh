#!/bin/zsh
# Builds "Boat Deck.app" and installs it to ~/Applications.
set -e
cd "$(dirname "$0")"
echo "▸ Compiling (release)…"
swift build -c release 2>&1 | grep -v "^\[" || true
BIN=$(swift build -c release --show-bin-path)/BoatDeck
[ -x "$BIN" ] || { echo "✗ Build failed"; swift build -c release; exit 1; }

APP="build/Boat Deck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BoatDeck"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f icon.png ]; then
  echo "▸ Making icon…"
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Signing (ad-hoc)…"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" || echo "(signing skipped)"

mkdir -p "$HOME/Applications"
osascript -e 'quit app id "dev.boat.BoatDeck"' 2>/dev/null || true
sleep 1; pkill -x BoatDeck 2>/dev/null || true
rm -rf "$HOME/Applications/Boat Deck.app"
cp -R "$APP" "$HOME/Applications/"
echo "✓ Installed to ~/Applications/Boat Deck.app"
[ "$1" = "--no-open" ] || open "$HOME/Applications/Boat Deck.app"
