#!/bin/zsh
# Foundation-only regression runner: also works with Command Line Tools, without XCTest.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  Sources/BoatDeck/JSON.swift Sources/BoatDeck/API.swift Sources/BoatDeck/System.swift Sources/BoatDeck/Trace.swift Sources/BoatDeck/ProcessRunner.swift Sources/BoatDeck/EventPager.swift Sources/BoatDeck/LocalFiles.swift \
  Tests/BoatDeckTests/*.swift -o "$TEST_DIR/regressions"
"$TEST_DIR/regressions"
