#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
CHECKOUT="${1:?Usage: sudo bash update.sh /path/to/reviewed/checkout FULL_COMMIT_SHA}"
EXPECTED="${2:?Provide the approved full commit SHA}"
[[ "$EXPECTED" =~ ^[0-9a-f]{40}$ ]] || { echo "A full commit SHA is required." >&2; exit 1; }
# The admin fetches private GitHub code with their own credentials, not the kiosk.
ACTUAL=$(git -c safe.directory="$CHECKOUT" -C "$CHECKOUT" rev-parse HEAD)
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "Checkout does not match approved commit." >&2; exit 1; }
[[ -z "$(git -c safe.directory="$CHECKOUT" -C "$CHECKOUT" status --porcelain)" ]] || { echo "Checkout must be clean." >&2; exit 1; }
# Export only committed files. Never copy Git credentials or untracked content.
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT
git -c safe.directory="$CHECKOUT" -C "$CHECKOUT" archive "$EXPECTED" | tar -x -C "$STAGE"
NECD_ASSUME_YES=1 bash "$STAGE/install.sh"
printf '%s\n' "$EXPECTED" > /etc/necd-kiosk/installed-commit
systemctl restart greetd
echo "Updated. Staff must reauthenticate CareStack and select the office."
