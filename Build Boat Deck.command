#!/bin/zsh
# Builds Boat Deck, then keeps watching: whenever a file named .rebuild appears
# in this folder, it rebuilds (so fixes can be applied without another double-click).
# Close this window to stop watching.
cd "$(dirname "$0")"
build() {
  zsh ./build.sh "$@" 2>&1 | tee build.log
  echo "EXIT:${pipestatus[1]}" >> build.log
}
chmod +x build.sh
build
echo "\n👀 Watching for rebuild requests… (close this window to stop)"
while true; do
  if [ -f .rebuild ]; then
    rm -f .rebuild
    echo "\n── Rebuild requested $(date +%H:%M:%S) ──"
    build
  fi
  sleep 2
done
