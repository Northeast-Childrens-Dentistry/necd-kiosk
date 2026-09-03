#!/usr/bin/env bash
set -u

printf '\nNECD Kiosk Diagnostics\n'
printf '======================\n'
printf 'Hostname:      %s\n' "$(hostname)"
printf 'Date:          %s\n' "$(date -Is)"
printf 'Kernel:        %s\n' "$(uname -r)"
printf 'Architecture:  %s\n' "$(dpkg --print-architecture 2>/dev/null || uname -m)"
printf 'Memory:        %s\n' "$(free -h | awk '/Mem:/ {print $2 " total, " $3 " used, " $7 " available"}')"
printf 'Root disk:     %s\n' "$(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free (" $5 ")"}')"
printf '\nServices\n--------\n'
for svc in greetd ssh tailscaled; do
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    printf '%-12s %s\n' "$svc:" "$(systemctl is-active "$svc" 2>/dev/null || true)"
  else
    printf '%-12s not installed\n' "$svc:"
  fi
done

printf '\nApplications\n------------\n'
printf 'Cage:          %s\n' "$(command -v cage >/dev/null && cage --version 2>/dev/null | head -n1 || echo missing)"
printf 'Chromium:      %s\n' "$(command -v chromium >/dev/null && chromium --version 2>/dev/null || echo missing)"
printf 'Tailscale:     %s\n' "$(command -v tailscale >/dev/null && tailscale version 2>/dev/null | head -n1 || echo missing)"

printf '\nNetwork\n-------\n'
printf 'Default route: %s\n' "$(ip route show default 2>/dev/null | head -n1 || echo none)"
if command -v tailscale >/dev/null 2>&1; then
  printf 'Tailscale IP:  %s\n' "$(tailscale ip -4 2>/dev/null | head -n1 || echo not-authenticated)"
fi

printf '\nCareStack\n---------\n'
if curl -fsSIL --max-time 10 'https://patientportal-mw.carestack.com/' >/dev/null 2>&1; then
  echo 'Reachable:     yes'
else
  echo 'Reachable:     no'
fi

if [[ -f /etc/necd-kiosk/device.conf ]]; then
  printf '\nDevice configuration\n--------------------\n'
  cat /etc/necd-kiosk/device.conf
fi

printf '\nRecent kiosk service log\n-------------------------\n'
journalctl -u greetd -n 15 --no-pager 2>/dev/null || true
