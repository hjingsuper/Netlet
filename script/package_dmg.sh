#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-.build/netlet-bundle.noindex/Netlet.app}"
OUTPUT_PATH="${2:-Netlet-Apple-Silicon.dmg}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMGBUILD_BIN="${DMGBUILD_BIN:-$(command -v dmgbuild || true)}"

if [[ -z "$DMGBUILD_BIN" ]]; then
  PYTHON_USER_BASE="$(python3 -m site --user-base)"
  if [[ -x "$PYTHON_USER_BASE/bin/dmgbuild" ]]; then
    DMGBUILD_BIN="$PYTHON_USER_BASE/bin/dmgbuild"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 1
fi
if [[ -z "$DMGBUILD_BIN" || ! -x "$DMGBUILD_BIN" ]]; then
  echo "dmgbuild is required (tested with 1.6.5)" >&2
  exit 1
fi

if [[ "$APP_PATH" != /* ]]; then
  APP_PATH="$PWD/$APP_PATH"
fi
if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PWD/$OUTPUT_PATH"
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"

"$DMGBUILD_BIN" \
  -s "$ROOT_DIR/script/dmg_settings.py" \
  -D app_path="$APP_PATH" \
  -D background_path="$ROOT_DIR/Assets/dmg-background.png" \
  -D volume_icon_path="$ROOT_DIR/Assets/AppIcon.icns" \
  "Netlet v$APP_VERSION" \
  "$OUTPUT_PATH"

echo "created: $OUTPUT_PATH"
