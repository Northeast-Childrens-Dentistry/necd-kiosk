#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
umask 077
OUT_DIR="${1:-/tmp}"
[[ "$OUT_DIR" == /* && -d "$OUT_DIR" ]] || { echo "Use an existing absolute output directory." >&2; exit 1; }
BUNDLE_DIR=$(mktemp -d)
trap 'rm -rf -- "$BUNDLE_DIR"' EXIT
write_cmd() { local file="$1"; shift; "$@" > "$BUNDLE_DIR/$file" 2>&1 || true; }
write_cmd os.txt cat /etc/os-release
write_cmd memory.txt free -h
write_cmd disk.txt df -h /
write_cmd chromium.txt chromium --version
write_cmd cage.txt cage --version
write_cmd tailscale.txt tailscale version
for svc in greetd ssh tailscaled; do
  systemctl show "$svc" --property=ActiveState,SubState,Result > "$BUNDLE_DIR/$svc.txt" || true
done
if [[ -f /etc/necd-kiosk/installed-commit ]]; then
  cp /etc/necd-kiosk/installed-commit "$BUNDLE_DIR/"
fi
cat > "$BUNDLE_DIR/README.txt" <<'EOF'
NECD minimal support report.
No browser profiles, URLs, configuration, journals, process arguments,
screenshots, network inventory, or authentication state are collected.
Review before sharing; request additional diagnostics through approved IT channels.
EOF
ARCHIVE=$(mktemp "$OUT_DIR/necd-kiosk-support-XXXXXXXX.tar.gz")
tar -C "$BUNDLE_DIR" -czf "$ARCHIVE" .
chmod 0600 "$ARCHIVE"
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
  chown "$SUDO_USER" "$ARCHIVE"
fi
printf '\nNECD support bundle:\n%s\n' "$ARCHIVE"
