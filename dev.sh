#!/bin/bash
#
# dev.sh — build cqlb, wrap it in a .app bundle, ad-hoc sign it, and
# install to /Applications/. Since cqlb is now a regular menu bar app
# (not an IME), this is an ordinary Mac app install.
#
# First run: macOS will ask for Accessibility permission. Grant it in
# System Settings → Privacy & Security → Accessibility, then relaunch.
#
# Usage:
#   ./dev.sh                    # debug build, install to /Applications
#   ./dev.sh --release          # release build
#   ./dev.sh --no-install       # build bundle only
#   ./dev.sh --install-user     # install to ~/Applications instead

set -euo pipefail

cd "$(dirname "$0")"

CONFIG="debug"
INSTALL=1
INSTALL_DIR="/Applications"
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG="release" ;;
    --no-install) INSTALL=0 ;;
    --install-user) INSTALL_DIR="$HOME/Applications" ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
  esac
done

BUILD_FLAG="-c $CONFIG"
BUILD_DIR=".build/$CONFIG"
BUNDLE_DIR="dist/cqlb.app"
SETTINGS_BUNDLE_DIR="dist/cqlb Settings.app"
DICTS_SRC="$HOME/Library/Rime"
OPENCC_SRC="$HOME/Library/Rime/opencc"

echo "==> swift build ($CONFIG)"
swift build $BUILD_FLAG --product cqlb >/dev/null
swift build $BUILD_FLAG --product cqlb-settings >/dev/null
BIN_PATH="$BUILD_DIR/cqlb"
SETTINGS_BIN_PATH="$BUILD_DIR/cqlb-settings"
if [ ! -x "$BIN_PATH" ]; then
  echo "error: cqlb binary not found at $BIN_PATH" >&2
  exit 1
fi
if [ ! -x "$SETTINGS_BIN_PATH" ]; then
  echo "error: cqlb-settings binary not found at $SETTINGS_BIN_PATH" >&2
  exit 1
fi

echo "==> generating icon"
if [ ! -f Resources/cqlb.pdf ]; then
  swift scripts/gen-icon.swift Resources/cqlb.pdf 两 2>/dev/null
fi

echo "==> assembling $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources/Dicts"

cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/cqlb"
cp Resources/Info.plist "$BUNDLE_DIR/Contents/Info.plist"
cp Resources/cqlb.pdf "$BUNDLE_DIR/Contents/Resources/cqlb.pdf"

for f in cqlb.dict.yaml cqlb.src.dict.yaml ipinyin.dict.yaml english.dict.yaml; do
  if [ -f "$DICTS_SRC/$f" ]; then
    cp "$DICTS_SRC/$f" "$BUNDLE_DIR/Contents/Resources/Dicts/$f"
  fi
done
for f in emoji_word.txt emoji_category.txt; do
  if [ -f "$OPENCC_SRC/$f" ]; then
    cp "$OPENCC_SRC/$f" "$BUNDLE_DIR/Contents/Resources/Dicts/$f"
  fi
done

# Strip any quarantine attributes that came along with the source dict files.
xattr -cr "$BUNDLE_DIR" 2>/dev/null || true

echo "==> assembling $SETTINGS_BUNDLE_DIR"
rm -rf "$SETTINGS_BUNDLE_DIR"
mkdir -p "$SETTINGS_BUNDLE_DIR/Contents/MacOS"
mkdir -p "$SETTINGS_BUNDLE_DIR/Contents/Resources"
cp "$SETTINGS_BIN_PATH" "$SETTINGS_BUNDLE_DIR/Contents/MacOS/cqlb-settings"
cp Resources/Settings-Info.plist "$SETTINGS_BUNDLE_DIR/Contents/Info.plist"
cp Resources/cqlb.pdf "$SETTINGS_BUNDLE_DIR/Contents/Resources/cqlb.pdf"
xattr -cr "$SETTINGS_BUNDLE_DIR" 2>/dev/null || true

echo "==> ensuring self-signed cert"
bash scripts/setup-cert.sh

echo "==> codesign with cqlb-dev cert"
for bundle in "$BUNDLE_DIR" "$SETTINGS_BUNDLE_DIR"; do
  codesign --force --deep --sign "cqlb-dev" --options runtime "$bundle" 2>&1 \
    || {
      echo "codesign with cqlb-dev failed for $bundle, falling back to ad-hoc" >&2
      codesign --force --deep --sign - "$bundle" >/dev/null 2>&1
    }
done

if [ "$INSTALL" -eq 1 ]; then
  mkdir -p "$INSTALL_DIR"
  DEST="$INSTALL_DIR/cqlb.app"
  SETTINGS_DEST="$INSTALL_DIR/cqlb Settings.app"
  echo "==> installing to $DEST"
  killall cqlb 2>/dev/null || true
  killall cqlb-settings 2>/dev/null || true

  install_one() {
    local src="$1"
    local dst="$2"
    if [ -w "$INSTALL_DIR" ] || [ "$INSTALL_DIR" = "$HOME/Applications" ]; then
      rm -rf "$dst"
      ditto "$src" "$dst"
    else
      sudo rm -rf "$dst"
      sudo ditto "$src" "$dst"
    fi
    xattr -cr "$dst" 2>/dev/null || true
    codesign --force --deep --sign "cqlb-dev" --options runtime "$dst" 2>&1 \
      || codesign --force --deep --sign - "$dst" >/dev/null 2>&1
  }

  install_one "$BUNDLE_DIR" "$DEST"
  install_one "$SETTINGS_BUNDLE_DIR" "$SETTINGS_DEST"

  echo ""
  echo "cqlb installed to $DEST"
  echo "cqlb Settings installed to $SETTINGS_DEST"
  echo ""
  echo "Next steps:"
  echo "  1. Launch it:"
  echo "       open '$DEST'"
  echo "  2. Press Caps Lock to toggle Chinese input. Type 'aajj' to test."
  echo "  3. Open settings from the menu bar icon → 设置…"
  echo ""
  echo "To see logs while testing:"
  echo "  tail -f /tmp/cqlb.log"
else
  echo ""
  echo "bundles ready at $BUNDLE_DIR and $SETTINGS_BUNDLE_DIR (not installed)."
fi
