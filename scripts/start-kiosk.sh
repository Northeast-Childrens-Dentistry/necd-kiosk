#!/usr/bin/env bash
set -euo pipefail
# Root-owned configuration. Never source files writable by the kiosk user.
# shellcheck disable=SC1091
source /etc/necd-kiosk/device.conf
: "${XDG_RUNTIME_DIR:?greetd/PAM must provide a runtime directory}"
[[ "$CARESTACK_URL" == https://* ]] || exit 1
# Runtime directory is tmpfs; discard the previous browser session on restart.
PROFILE_DIR="$XDG_RUNTIME_DIR/necd-chromium"
rm -rf -- "$PROFILE_DIR"
install -d -m 0700 "$PROFILE_DIR"
exec /usr/bin/chromium \
  --ozone-platform=wayland --kiosk --no-first-run \
  --no-default-browser-check --disable-session-crashed-bubble \
  --disable-features=Translate --disable-breakpad \
  --user-data-dir="$PROFILE_DIR" "$CARESTACK_URL"
