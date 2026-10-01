#!/bin/zsh
# Verify failure handling without touching any installed application.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/repo"
cp build.sh "$TEST_DIR/repo/"
cat > "$TEST_DIR/bin/xcrun" <<'STUB'
#!/bin/sh
echo 26.0
STUB
cat > "$TEST_DIR/bin/swift" <<'STUB'
#!/bin/sh
echo 'compiler stopped without an error diagnostic' >&2
exit 23
STUB
chmod +x "$TEST_DIR/bin/"*
result=0
PATH="$TEST_DIR/bin:$PATH" zsh "$TEST_DIR/repo/build.sh" --build-only > "$TEST_DIR/output" 2>&1 || result=$?
[[ $result -eq 23 ]] || { cat "$TEST_DIR/output"; echo "Lost compiler exit code: $result"; exit 1; }
[[ ! -d "$TEST_DIR/repo/build" ]] || { echo "Build continued after compilation failed"; exit 1; }
cat > "$TEST_DIR/bin/xcrun" <<'STUB'
#!/bin/sh
echo 15.5
STUB
result=0
PATH="$TEST_DIR/bin:$PATH" zsh "$TEST_DIR/repo/build.sh" --build-only > "$TEST_DIR/output" 2>&1 || result=$?
[[ $result -eq 1 ]] || { echo "Old SDK was not rejected"; exit 1; }
echo "Build failure and SDK checks passed."
