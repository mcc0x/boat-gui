#!/bin/zsh
# Builds "Boat Deck.app" and installs it to ~/Applications.
set -e
cd "$(dirname "$0")"
# Diagnostics hook: if .sample exists, capture a stack sample of the running app instead of building.
if [ -f .sample ]; then
  rm -f .sample
  echo "▸ Sampling BoatDeck for 3s…"
  sample BoatDeck 3 -mayDie -file "$PWD/sample.txt" >/dev/null 2>&1 && echo "✓ sample.txt written" || echo "✗ sample failed"
  ps -o %cpu=,rss= -p $(pgrep -x BoatDeck) 2>/dev/null | sed 's/^/cpu,rss: /'
  exit 0
fi
echo "▸ Compiling (release)…"
OUT=$(swift build -c release 2>&1 || true)
print -r -- "$OUT" | grep -v "^\[" || true
if print -r -- "$OUT" | grep -q "error:"; then echo "✗ Build failed"; exit 1; fi
BIN=$(swift build -c release --show-bin-path)/BoatDeck
[ -x "$BIN" ] || { echo "✗ Build failed"; exit 1; }

# Assemble the bundle outside ~/Documents so no Finder/provenance metadata sneaks in.
STAGE=$(mktemp -d /tmp/boatdeck.XXXXXX)
APP="$STAGE/Boat Deck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto --norsrc --noextattr --noqtn "$BIN" "$APP/Contents/MacOS/BoatDeck"
ditto --norsrc --noextattr --noqtn Info.plist "$APP/Contents/Info.plist"

if [ -f icon.png ]; then
  echo "▸ Making icon…"
  ICONSET="$STAGE/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

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
  : > run.log
  open "$HOME/Applications/Boat Deck.app" 2>>run.log || { sleep 2; open "$HOME/Applications/Boat Deck.app" 2>>run.log || true; }
  sleep 4
  if pgrep -x BoatDeck >/dev/null; then echo "✓ Running"; else echo "✗ App is not running — see run.log"; fi
fi
