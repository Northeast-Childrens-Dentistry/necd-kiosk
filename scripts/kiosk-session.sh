#!/usr/bin/env bash
set -euo pipefail

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export XDG_SESSION_DESKTOP=cage

exec /usr/bin/cage -- /opt/necd-kiosk/scripts/start-kiosk.sh
