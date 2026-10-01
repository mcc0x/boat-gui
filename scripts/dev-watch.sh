#!/bin/zsh
# Development loop: builds once, then rebuilds whenever a file named `.rebuild` appears in the repo root
# (e.g. `touch .rebuild` from an editor hook or another machine). Ctrl-C or close the window to stop.
cd "$(dirname "$0")/.."
build() {
  zsh ./build.sh "$@" 2>&1 | tee build.log
  echo "EXIT:${pipestatus[1]}" >> build.log
}
build
echo "\n👀 Watching for .rebuild… (Ctrl-C to stop)"
while true; do
  if [ -f .rebuild ]; then
    rm -f .rebuild
    echo "\n── Rebuild requested $(date +%H:%M:%S) ──"
    build
  fi
  sleep 2
done
