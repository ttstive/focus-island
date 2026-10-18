#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/focus-island-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/focus-island-swift"
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="dist/Focus Island.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Remove a stale development-layout resource bundle from older local builds.
if [[ -d "$APP/FocusIsland_FocusIsland.bundle" ]]; then
  rm -rf "$APP/FocusIsland_FocusIsland.bundle"
fi
cp "$BIN_DIR/FocusIsland" "$APP/Contents/MacOS/FocusIsland"
./scripts/build-icon.sh
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/FocusIsland/Resources/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
if [[ -d "$BIN_DIR/FocusIsland_FocusIsland.bundle" ]]; then
  /usr/bin/ditto "$BIN_DIR/FocusIsland_FocusIsland.bundle" "$APP/Contents/Resources/FocusIsland_FocusIsland.bundle"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FocusIsland</string>
<key>CFBundleIdentifier</key><string>org.focusisland.app</string>
<key>CFBundleName</key><string>Focus Island</string>
<key>CFBundleDisplayName</key><string>Focus Island</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Focus-Island-macOS.zip
printf 'Built %s\n' "$APP"
