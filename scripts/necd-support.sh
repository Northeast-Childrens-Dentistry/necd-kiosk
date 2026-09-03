#!/usr/bin/env bash
set -euo pipefail

SUPPORT_SCRIPT="/opt/necd-kiosk/scripts/support-bundle.sh"
OUT_DIR="${1:-/tmp}"

if [[ $EUID -ne 0 ]]; then
  echo "Run this command with sudo:"
  echo "  sudo necd-support"
  exit 1
fi

if [[ ! -x "$SUPPORT_SCRIPT" ]]; then
  echo "ERROR: Support bundle script not found at $SUPPORT_SCRIPT" >&2
  exit 1
fi

printf '\nNECD Support\n============\n'
printf 'Collecting kiosk diagnostics...\n'

OUTPUT="$($SUPPORT_SCRIPT "$OUT_DIR")"
printf '%s\n' "$OUTPUT"

ARCHIVE="$(printf '%s\n' "$OUTPUT" | grep -E '^/.*necd-kiosk-support-.*\.tar\.gz$' | tail -n1 || true)"
HOST="$(hostname 2>/dev/null || echo kiosk)"
ADMIN_USER="${SUDO_USER:-}"

if [[ -z "$ADMIN_USER" || "$ADMIN_USER" == "root" ]]; then
  ADMIN_USER="YOUR_USERNAME"
fi

if [[ -n "$ARCHIVE" ]]; then
  printf '\nTo copy this file to your computer over Tailscale/SSH, run this on your computer:\n\n'
  printf '  scp %s@%s:%q .\n\n' "$ADMIN_USER" "$HOST" "$ARCHIVE"
  printf 'Then upload the .tar.gz file to ChatGPT for troubleshooting.\n'
fi
