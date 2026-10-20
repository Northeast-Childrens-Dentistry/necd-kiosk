#!/usr/bin/env bash
set -u
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export XDG_SESSION_DESKTOP=cage
ulimit -c 0
while true; do
  /usr/bin/dbus-run-session -- /usr/bin/cage -- /opt/necd-kiosk/scripts/start-kiosk.sh
  rc=$?
  echo "NECD kiosk exited with code $rc; restarting in 5 seconds." >&2
  sleep 5
done
