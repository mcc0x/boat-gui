#!/bin/zsh
# Build a local ad-hoc-signed app. No Apple developer account is required.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-install-open}"
case "$MODE" in
  install-open|--no-open|--build-only) ;;
  --help|-h)
    echo "Usage: ./build.sh [--no-open | --build-only]"
    echo "Default: build, install to ~/Applications, and launch."
    echo "--build-only: produce build/Boat Deck.app without installing or launching."
    exit 0 ;;
  *) echo "Unknown option: $MODE" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Pass only one build option." >&2; exit 2; }

SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
if (( ${SDK_VERSION%%.*} < 26 )); then
  echo "Boat Deck needs the macOS 26+ SDK to build. Select Xcode 26+ or Command Line Tools 26+." >&2
  exit 1
fi

echo "▸ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/BoatDeck"
[[ -x "$BIN" ]] || { echo "Build did not produce BoatDeck." >&2; exit 1; }

mkdir -p build
STAGE=$(mktemp -d "$PWD/build/.stage.XXXXXX")
INSTALL_STAGE=""
BACKUP=""
DEST="$HOME/Applications/Boat Deck.app"
cleanup() {
  local result=$?
  if [[ -n "$BACKUP" && -d "$BACKUP" && ! -e "$DEST" ]]; then
    mv "$BACKUP" "$DEST" || true
  fi
  rm -rf "$STAGE"
  [[ -z "$INSTALL_STAGE" ]] || rm -rf "$INSTALL_STAGE"
  return $result
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
rm -rf "build/Boat Deck.app"
mv "$APP" "build/Boat Deck.app"
echo "✓ Built build/Boat Deck.app"
[[ "$MODE" != --build-only ]] || exit 0

# Prepare the replacement before touching the installed app.
mkdir -p "$HOME/Applications"
INSTALL_STAGE=$(mktemp -d "$HOME/Applications/.boatdeck-install.XXXXXX")
ditto --norsrc --noextattr "build/Boat Deck.app" "$INSTALL_STAGE/Boat Deck.app"
codesign --verify --strict "$INSTALL_STAGE/Boat Deck.app"
if pgrep -x BoatDeck >/dev/null; then
  osascript -e 'tell application id "dev.boat.BoatDeck" to quit'
  for i in {1..20}; do pgrep -x BoatDeck >/dev/null || break; sleep 0.5; done
  if pgrep -x BoatDeck >/dev/null; then
    echo "Quit Boat Deck, then run this command again to install." >&2
    exit 1
  fi
fi
if [[ -e "$DEST" ]]; then
  BACKUP="$INSTALL_STAGE/previous.app"
  mv "$DEST" "$BACKUP"
fi
mv "$INSTALL_STAGE/Boat Deck.app" "$DEST"
echo "✓ Installed to ~/Applications/Boat Deck.app"
[[ "$MODE" == --no-open ]] || open "$DEST"
