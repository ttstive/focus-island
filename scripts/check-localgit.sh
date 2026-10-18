#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/focus-island-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/focus-island-swift"
swift build --disable-sandbox --product FocusIsland
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/focus-island-runner.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 6 -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
  -I "$BIN_DIR/Modules" \
  "$BIN_DIR/FocusCore.build/Activity.swift.o" \
  "$BIN_DIR/FocusCore.build/EditorCatalog.swift.o" \
  "$BIN_DIR/FocusCore.build/Commits.swift.o" \
  "$BIN_DIR/FocusCore.build/SessionConsent.swift.o" \
  Sources/FocusIsland/LocalGit.swift scripts/check-localgit.swift \
  -o "$CHECK_DIR/check-localgit"
"$CHECK_DIR/check-localgit" "$@"
