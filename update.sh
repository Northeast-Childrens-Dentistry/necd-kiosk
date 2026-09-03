#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

INSTALL_DIR="/opt/necd-kiosk"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  echo "NECD kiosk repository not found at $INSTALL_DIR" >&2
  exit 1
fi

cd "$INSTALL_DIR"
git fetch --prune origin
git pull --ff-only origin main

install -m 0755 scripts/*.sh /opt/necd-kiosk/scripts/
install -d -m 0755 /etc/opt/chrome/policies/managed
install -m 0644 chrome/necd-kiosk.json /etc/opt/chrome/policies/managed/necd-kiosk.json

systemctl restart greetd

echo "NECD kiosk updated and restarted."
