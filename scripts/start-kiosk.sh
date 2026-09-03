#!/usr/bin/env bash
set -euo pipefail

CARESTACK_URL="${CARESTACK_URL:-https://patientportal-mw.carestack.com/?dn=necdsa#/patient-connect}"
PROFILE_DIR="${HOME}/.config/necd-chrome"

mkdir -p "$PROFILE_DIR"

exec /usr/bin/google-chrome-stable \
  --ozone-platform=wayland \
  --kiosk \
  --no-first-run \
  --no-default-browser-check \
  --disable-session-crashed-bubble \
  --disable-infobars \
  --disable-translate \
  --disable-features=Translate \
  --user-data-dir="$PROFILE_DIR" \
  "$CARESTACK_URL"
