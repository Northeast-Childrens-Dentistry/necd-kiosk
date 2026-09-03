#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$HOME}"
STAMP="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname 2>/dev/null || echo unknown-host)"
BUNDLE_DIR="$(mktemp -d)"
ARCHIVE="${OUT_DIR%/}/necd-kiosk-support-${HOST}-${STAMP}.tar.gz"

cleanup() {
  rm -rf "$BUNDLE_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

write_cmd() {
  local file="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n\n'
    "$@" 2>&1 || true
  } > "$BUNDLE_DIR/$file"
}

cat > "$BUNDLE_DIR/README.txt" <<'EOF'
NECD Kiosk Support Bundle
========================

This bundle is intended for troubleshooting NECD kiosk software and hardware.

It intentionally does NOT collect:
- Chromium browser profile data
- cookies or saved sessions
- browser history
- CareStack credentials
- CareStack form contents
- screenshots
- patient names or other patient data
- Tailscale authentication keys

Review the text files before sharing if desired.
EOF

# Core diagnostics
if [[ -x /opt/necd-kiosk/scripts/diagnose.sh ]]; then
  /opt/necd-kiosk/scripts/diagnose.sh > "$BUNDLE_DIR/diagnose.txt" 2>&1 || true
fi

write_cmd os-release cat /etc/os-release
write_cmd uname.txt uname -a
write_cmd uptime.txt uptime
write_cmd memory.txt free -h
write_cmd disk.txt df -hT
write_cmd block-devices.txt lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
write_cmd pci.txt lspci -nn
write_cmd usb.txt lsusb
write_cmd ip-address.txt ip -brief address
write_cmd routes.txt ip route
write_cmd dns.txt cat /etc/resolv.conf
write_cmd chromium-version.txt chromium --version
write_cmd cage-version.txt cage --version
write_cmd tailscale-version.txt tailscale version
write_cmd tailscale-status.txt tailscale status

# Service state and logs. Keep logs bounded so the bundle stays small.
write_cmd services.txt systemctl --no-pager --full status greetd ssh tailscaled
journalctl -u greetd --since "24 hours ago" --no-pager > "$BUNDLE_DIR/greetd-journal.txt" 2>&1 || true
journalctl -u tailscaled --since "24 hours ago" --no-pager > "$BUNDLE_DIR/tailscaled-journal.txt" 2>&1 || true
journalctl -p warning..alert --since "24 hours ago" --no-pager > "$BUNDLE_DIR/system-warnings.txt" 2>&1 || true
journalctl -b --no-pager -n 500 > "$BUNDLE_DIR/current-boot-last-500.txt" 2>&1 || true

# Configuration files that should not contain secrets.
if [[ -f /etc/necd-kiosk/device.conf ]]; then
  cp /etc/necd-kiosk/device.conf "$BUNDLE_DIR/device.conf"
fi
if [[ -f /etc/chromium/policies/managed/necd-kiosk.json ]]; then
  cp /etc/chromium/policies/managed/necd-kiosk.json "$BUNDLE_DIR/chromium-policy.json"
fi
if [[ -f /etc/greetd/config.toml ]]; then
  cp /etc/greetd/config.toml "$BUNDLE_DIR/greetd-config.toml"
fi

# Repository/version information when installed from git.
if [[ -d /opt/necd-kiosk/.git ]]; then
  git -C /opt/necd-kiosk status --short --branch > "$BUNDLE_DIR/git-status.txt" 2>&1 || true
  git -C /opt/necd-kiosk log -1 --oneline > "$BUNDLE_DIR/git-version.txt" 2>&1 || true
fi

# Basic reachability checks without recording patient-specific URLs.
{
  echo "CareStack base reachability:"
  curl -fsSI --max-time 10 https://patientportal-mw.carestack.com/ | head -n 10 || true
  echo
  echo "GitHub reachability:"
  curl -fsSI --max-time 10 https://github.com/ | head -n 10 || true
} > "$BUNDLE_DIR/reachability.txt" 2>&1

# Package versions useful for reproducibility.
dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null | \
  grep -E '^(chromium|cage|greetd|openssh|tailscale|linux-image)' \
  > "$BUNDLE_DIR/relevant-packages.txt" || true

# Generate a simple manifest.
(
  cd "$BUNDLE_DIR"
  sha256sum ./* 2>/dev/null || true
) > "$BUNDLE_DIR/SHA256SUMS.txt"

tar -C "$BUNDLE_DIR" -czf "$ARCHIVE" .
chmod 0644 "$ARCHIVE"

printf '\nNECD kiosk support bundle created:\n%s\n\n' "$ARCHIVE"
printf 'You can upload this .tar.gz file directly to ChatGPT for troubleshooting.\n'
printf 'No Chromium profile, cookies, CareStack credentials, screenshots, or patient data are intentionally collected.\n'
