#!/bin/bash
#
# dev.sh — IME-only development wrapper.
#
# Usage:
#   ./dev.sh                    # debug build + install IME
#   ./dev.sh --release          # release build + install IME
#   ./dev.sh --no-install       # build IME only
#   ./dev.sh --package          # release build + install + notarize + zip

set -euo pipefail

cd "$(dirname "$0")"

CONFIG="debug"
INSTALL=1
PACKAGE=0
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG="release" ;;
    --no-install) INSTALL=0 ;;
    --package) PACKAGE=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
  esac
done

if [ "$PACKAGE" -eq 1 ]; then
  exec make package-ime
elif [ "$INSTALL" -eq 1 ]; then
  exec make CONFIG="$CONFIG" install-ime
else
  exec make CONFIG="$CONFIG" build-ime
fi
