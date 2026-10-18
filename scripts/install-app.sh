#!/bin/zsh
set -eu
cd "${0:A:h}/.."
./scripts/build-app.sh
APPS_DIRECTORY="${1:-$HOME/Applications}"
INSTALLED_APP="$APPS_DIRECTORY/Focus Island.app"
if [[ -e "$INSTALLED_APP" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$BUNDLE_ID" != "org.focusisland.app" ]]; then
    print -u2 'The destination contains a different app. Choose another Applications directory.'
    exit 1
  fi
fi
mkdir -p "$APPS_DIRECTORY"
/usr/bin/ditto "dist/Focus Island.app" "$INSTALLED_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP"
/usr/bin/mdimport "$INSTALLED_APP" >/dev/null 2>&1 || true
printf 'Installed %s\nFind Focus Island in Spotlight, or open the app from this folder.\n' "$INSTALLED_APP"
