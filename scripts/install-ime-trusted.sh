#!/bin/bash
#
# install-ime-trusted.sh — attempt to install cqlb-ime as a system-wide IME
# with the self-signed `cqlb-dev` certificate added to the System keychain
# and marked as trusted for code signing.
#
# This is a workaround for macOS 15+/26 which normally requires Apple
# Developer ID signatures to load third-party input methods. Success
# depends on Apple's exact policy in your macOS version — on very recent
# builds even trusted self-signed certs may still be filtered.
#
# Requires sudo. Usage: bash scripts/install-ime-trusted.sh

set -euo pipefail

CERT_NAME="cqlb-dev"
SYSTEM_DEST="/Library/Input Methods/cqlb-ime.app"
SRC_BUNDLE="${HOME}/Library/Input Methods/cqlb-ime.app"

if [ ! -d "$SRC_BUNDLE" ]; then
  echo "error: $SRC_BUNDLE not found. Run 'make install-ime' first." >&2
  exit 1
fi

echo "==> ensuring self-signed cert exists"
bash "$(dirname "$0")/setup-cert.sh"

echo "==> exporting cqlb-dev cert to /tmp/cqlb-dev.cer"
# -p = PEM; we re-import into System keychain with trust settings
security find-certificate -c "$CERT_NAME" -p > /tmp/cqlb-dev.cer

echo "==> installing cert into System keychain with codeSign trust (requires sudo password)"
# If already present, this may fail; that's fine.
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain /tmp/cqlb-dev.cer || true

echo "==> copying bundle to $SYSTEM_DEST"
sudo rm -rf "$SYSTEM_DEST"
sudo ditto "$SRC_BUNDLE" "$SYSTEM_DEST"
sudo chown -R root:wheel "$SYSTEM_DEST"

# Strip quarantine / extended attributes that might taint the signature.
sudo xattr -cr "$SYSTEM_DEST"

echo "==> re-signing with cqlb-dev (not ad-hoc)"
# Sign running under the user's HOME so codesign can access login.keychain.
sudo -E env HOME="$HOME" codesign --force --deep \
    --sign "$CERT_NAME" \
    --options runtime \
    --timestamp=none \
    "$SYSTEM_DEST" 2>&1

echo "==> verifying"
codesign -dvvv "$SYSTEM_DEST" 2>&1 | grep -E "Authority|Signature|flags" || true
echo ""
echo "==> refreshing LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$SYSTEM_DEST"

echo "==> restarting TextInputMenuAgent"
killall TextInputMenuAgent 2>/dev/null || true

echo ""
echo "DONE. Open System Settings → Keyboard → Text Input → Input Sources → +"
echo "and look for 超强两笔 under 简体中文."
