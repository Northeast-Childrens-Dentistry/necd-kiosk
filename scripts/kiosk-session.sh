#!/usr/bin/env bash
set -u

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export XDG_SESSION_DESKTOP=cage

# Keep the kiosk alive for the entire greeter session. If Chrome or Cage exits,
# wait briefly and start a clean session again.
while true; do
  /usr/bin/cage -- /opt/necd-kiosk/scripts/start-kiosk.sh
  rc=$?
  echo "NECD kiosk session exited with code $rc; restarting in 2 seconds." >&2
  sleep 2
done
