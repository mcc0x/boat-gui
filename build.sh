#!/bin/zsh
# Builds "Boat Deck.app" from source and installs it to ~/Applications.
#
#   ./build.sh            build, install and launch
#   ./build.sh --no-open  build and install only
#
# Needs only Apple's Command Line Tools (xcode-select --install); full Xcode is optional.
set -e
cd "$(dirname "$0")"

echo "▸ Compiling (release)…"
OUT=$(swift build -c release 2>&1 || true)
print -r -- "$OUT" | grep -v "^\[" || true
if print -r -- "$OUT" | grep -q "error:"; then echo "✗ Build failed"; exit 1; fi
BIN=$(swift build -c release --show-bin-path)/BoatDeck
[ -x "$BIN" ] || { echo "✗ Build failed"; exit 1; }

# Assemble the bundle in a temp dir so no Finder/provenance metadata ends up in it.
STAGE=$(mktemp -d /tmp/boatdeck.XXXXXX)
APP="$STAGE/Boat Deck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto --norsrc --noextattr --noqtn "$BIN" "$APP/Contents/MacOS/BoatDeck"
ditto --norsrc --noextattr --noqtn Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Making icon…"
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>&1 || echo "(signing skipped)"

echo "▸ Installing…"
osascript -e 'tell application id "dev.boat.BoatDeck" to quit' >/dev/null 2>&1 &
for i in 1 2 3 4 5 6; do pgrep -x BoatDeck >/dev/null || break; sleep 0.5; done
pkill -x BoatDeck 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Boat Deck.app"
ditto --norsrc --noextattr "$APP" "$HOME/Applications/Boat Deck.app"
rm -rf "$STAGE"
echo "✓ Installed to ~/Applications/Boat Deck.app"

if [ "$1" != "--no-open" ]; then
  open "$HOME/Applications/Boat Deck.app" || { sleep 2; open "$HOME/Applications/Boat Deck.app"; }
fi
