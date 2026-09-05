#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Netlet"
BUNDLE_ID="${NETLET_BUNDLE_ID:-com.hjingsuper.Netlet}"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${NETLET_CONFIGURATION:-debug}"
DISTRIBUTION_BUILD="${NETLET_DISTRIBUTION_BUILD:-1}"
SPARKLE_PUBLIC_KEY="${NETLET_SPARKLE_PUBLIC_KEY:-DC0ZIoIkcptg00FmyFYsrhx72e+U1X4S10mgGpAybV8=}"
SPARKLE_FEED_URL="https://github.com/hjingsuper/Netlet/releases/latest/download/appcast.xml"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="${NETLET_VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
APP_BUILD="${NETLET_BUILD_NUMBER:-$(tr -d '[:space:]' < "$ROOT_DIR/BUILD_NUMBER")}"
APP_STAGE_DIR="$ROOT_DIR/.build/netlet-bundle.noindex"
APP_BUNDLE="$APP_STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/AppIcon.icns"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! "$APP_VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "invalid Netlet version: $APP_VERSION" >&2
  exit 2
fi
if [[ ! "$APP_BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid Netlet build number: $APP_BUILD" >&2
  exit 2
fi
if [[ "$DISTRIBUTION_BUILD" != "0" && "$DISTRIBUTION_BUILD" != "1" ]]; then
  echo "NETLET_DISTRIBUTION_BUILD must be 0 or 1" >&2
  exit 2
fi
if [[ "$DISTRIBUTION_BUILD" == "1" && -z "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "NETLET_SPARKLE_PUBLIC_KEY is required for a distribution build" >&2
  exit 2
fi

DISTRIBUTION_BUILD_PLIST="<false/>"
if [[ "$DISTRIBUTION_BUILD" == "1" ]]; then
  DISTRIBUTION_BUILD_PLIST="<true/>"
fi

cd "$ROOT_DIR"

# The .noindex staging directory keeps generated bundles out of Spotlight and
# Launchpad search results, where they could otherwise appear beside the app
# installed in /Applications.
mkdir -p "$APP_STAGE_DIR"

if [[ "$MODE" == "run" || "$MODE" == "--ui" || "$MODE" == "ui" || "$MODE" == "--menu" || "$MODE" == "menu" || "$MODE" == "--verify" || "$MODE" == "verify" ]]; then
  while IFS= read -r app_pid; do
    app_command="$(ps -p "$app_pid" -o command= 2>/dev/null || true)"
    if [[ "$app_command" == "$APP_BINARY" || "$app_command" == "$APP_BINARY "* ]]; then
      kill "$app_pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -x "$APP_NAME" || true)
fi

swift build -c "$BUILD_CONFIGURATION"
BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
ditto "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$APP_RESOURCES/Netlet-LICENSE.txt"
cp "$ROOT_DIR/.build/checkouts/Sparkle/LICENSE" "$APP_RESOURCES/Sparkle-LICENSE.txt"
chmod +x "$APP_BINARY"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"

mkdir -p "$APP_RESOURCES/zh_CN.lproj" "$APP_RESOURCES/zh-Hans.lproj" "$APP_RESOURCES/en.lproj"
cat >"$APP_RESOURCES/zh_CN.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleDisplayName" = "Netlet";
"CFBundleName" = "Netlet";
STRINGS
cp "$APP_RESOURCES/zh_CN.lproj/InfoPlist.strings" "$APP_RESOURCES/zh-Hans.lproj/InfoPlist.strings"
cat >"$APP_RESOURCES/en.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleDisplayName" = "Netlet";
"CFBundleName" = "Netlet";
STRINGS

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>zh-Hans</string>
    <string>zh_CN</string>
    <string>en</string>
  </array>
  <key>CFBundleAllowMixedLocalizations</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 hjingsuper</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>21600</integer>
  <key>NetletDistributionBuild</key>
  $DISTRIBUTION_BUILD_PLIST
</dict>
</plist>
PLIST

# Netlet intentionally supports ad-hoc signing because no Apple Developer ID
# certificate is available. Sparkle distribution builds still require a
# separate EdDSA public key for downloaded-update verification.
codesign --force --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --ui|ui)
    /usr/bin/open -n "$APP_BUNDLE" --args --show-settings
    ;;
  --menu|menu)
    /usr/bin/open -n "$APP_BUNDLE" --args --show-menu
    ;;
  --package|package)
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--ui|--menu|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
