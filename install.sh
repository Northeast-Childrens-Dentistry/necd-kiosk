#!/usr/bin/env bash
set -euo pipefail

CARESTACK_URL="https://patientportal-mw.carestack.com/?dn=necdsa#/patient-connect"
INSTALL_DIR="/opt/necd-kiosk"
CONFIG_DIR="/etc/necd-kiosk"
KIOSK_USER="kiosk"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run this installer with sudo: sudo ./install.sh"
[[ -r /etc/os-release ]] || fail "Cannot identify this operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" && "${VERSION_CODENAME:-}" == "trixie" ]] || fail "Use Debian 13 (trixie) for this pilot."
[[ "$(dpkg --print-architecture)" == "amd64" ]] || fail "This prototype currently expects 64-bit x86 Debian (amd64)."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Preserve the station identity when reapplying an approved release.
if [[ -f "$CONFIG_DIR/device.conf" ]]; then
  # This file is root-owned shell configuration, never patient input.
  # shellcheck disable=SC1091
  source "$CONFIG_DIR/device.conf"
  NECD_LOCATION="${NECD_LOCATION:-$LOCATION}"
  NECD_STATION="${NECD_STATION:-$STATION}"
fi
CARESTACK_URL="${NECD_CARESTACK_URL:-$CARESTACK_URL}"
[[ "$CARESTACK_URL" == https://* && "$CARESTACK_URL" != *
printf '===========================\n'
printf 'This will convert this Debian computer into a single-purpose CareStack parent kiosk.\n\n'

LOCATIONS=(village southcross schertz downtown dominion northern-oaks)
DISPLAY_NAMES=("Village Drive" Southcross Schertz Downtown "Dominion Crossing" "Northern Oaks")

if [[ -n "${NECD_LOCATION:-}" ]]; then
  LOCATION="${NECD_LOCATION,,}"
else
  echo "Choose this kiosk's office:"
  for i in "${!LOCATIONS[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${DISPLAY_NAMES[$i]}"
  done
  while true; do
    read -r -p "Location [1-${#LOCATIONS[@]}]: " choice
    if [[ "$choice" =~ ^[1-6]$ ]]; then
      LOCATION="${LOCATIONS[$((choice-1))]}"
      break
    fi
    echo "Please enter a number from 1 to ${#LOCATIONS[@]}."
  done
fi

valid_location=false
for item in "${LOCATIONS[@]}"; do
  [[ "$LOCATION" == "$item" ]] && valid_location=true
done
$valid_location || fail "Unknown location: $LOCATION"

if [[ -n "${NECD_STATION:-}" ]]; then
  STATION="$NECD_STATION"
else
  read -r -p "Station number [1]: " STATION
  STATION="${STATION:-1}"
fi
[[ "$STATION" =~ ^[0-9]{1,2}$ ]] || fail "Station number must be numeric."
STATION=$((10#$STATION))
(( STATION >= 1 && STATION <= 99 )) || fail "Station number must be between 1 and 99."
STATION_PADDED="$(printf '%02d' "$STATION")"
HOSTNAME_NEW="${LOCATION}-kiosk-${STATION_PADDED}"

printf '\nConfiguration\n-------------\n'
printf 'Location:  %s\n' "$LOCATION"
printf 'Station:   %s\n' "$STATION_PADDED"
printf 'Hostname:  %s\n' "$HOSTNAME_NEW"
printf 'CareStack: %s\n' "$CARESTACK_URL"

if [[ "${NECD_ASSUME_YES:-0}" != "1" ]]; then
  read -r -p "Proceed with installation? [Y/n]: " confirm
  case "${confirm:-Y}" in
    Y|y|yes|YES) ;;
    *) echo "Installation cancelled."; exit 0 ;;
  esac
fi

log "Updating Debian package metadata"
export DEBIAN_FRONTEND=noninteractive
apt-get update

log "Installing kiosk and administration packages"
apt-get install -y \
  cage \
  greetd \
  chromium \
  ca-certificates \
  curl \
  wget \
  git \
  openssh-server \
  dbus-user-session \
  libpam-systemd \
  dbus-x11 \
  unattended-upgrades \
  pciutils \
  usbutils

log "Installing Tailscale"
install -d -m 0755 /usr/share/keyrings
curl --proto '=https' -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl --proto '=https' -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale

log "Creating unprivileged kiosk account"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$KIOSK_USER"
fi
if id -nG "$KIOSK_USER" | tr ' ' '\n' | grep -Eq '^(sudo|adm|docker|lxd)
for group in video render input; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$KIOSK_USER"
  fi
done

log "Installing NECD kiosk files"
mkdir -p "$INSTALL_DIR"
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  tar -C "$SCRIPT_DIR" --exclude=.git -cf - . | tar -C "$INSTALL_DIR" -xf -
fi
chown -R root:root "$INSTALL_DIR"
find "$INSTALL_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "$INSTALL_DIR/install.sh" "$INSTALL_DIR/update.sh"
install -m 0755 "$INSTALL_DIR/scripts/necd-support.sh" /usr/local/bin/necd-support

log "Writing device configuration"
mkdir -p "$CONFIG_DIR"
{
  printf 'DEVICE_TYPE=%q\n' parent-kiosk
  printf 'LOCATION=%q\n' "$LOCATION"
  printf 'STATION=%q\n' "$STATION_PADDED"
  printf 'HOSTNAME=%q\n' "$HOSTNAME_NEW"
  printf 'CARESTACK_URL=%q\n' "$CARESTACK_URL"
} > "$CONFIG_DIR/device.conf"
chown root:root "$CONFIG_DIR/device.conf"
chmod 0644 "$CONFIG_DIR/device.conf"
hostnamectl set-hostname "$HOSTNAME_NEW"

log "Installing managed Chromium policies"
mkdir -p /etc/chromium/policies/managed
install -m 0644 "$INSTALL_DIR/chrome/necd-kiosk.json" \
  /etc/chromium/policies/managed/necd-kiosk.json

log "Configuring automatic kiosk session"
AGREETY_BIN="$(command -v agreety || true)"
[[ -n "$AGREETY_BIN" ]] || fail "greetd installed but agreety was not found."
cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "$AGREETY_BIN --cmd /bin/bash"
user = "greeter"

[initial_session]
command = "$INSTALL_DIR/scripts/kiosk-session.sh"
user = "$KIOSK_USER"
EOF
chmod 0644 /etc/greetd/config.toml

log "Configuring services"
systemctl enable ssh.service
systemctl enable --now tailscaled.service
systemctl disable getty@tty1.service
systemctl enable greetd.service
cat > /etc/apt/apt.conf.d/52necd-kiosk <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/necd-kiosk.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl set-default graphical.target

# A kiosk should not enter system sleep/hibernate during office hours.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

log "Installation checks"
chromium_version="$(chromium --version 2>/dev/null || echo MISSING)"
cage_version="$(cage --version 2>/dev/null | head -n1 || echo MISSING)"

printf '\nNECD kiosk installation complete\n'
printf '================================\n'
printf 'Hostname:       %s\n' "$HOSTNAME_NEW"
printf 'Location:       %s\n' "$LOCATION"
printf 'Station:        %s\n' "$STATION_PADDED"
printf 'Chromium:       %s\n' "$chromium_version"
printf 'Cage:           %s\n' "$cage_version"
printf 'SSH:            installed/enabled\n'
printf 'Tailscale:      installed; authorization may still be required\n'
printf 'Kiosk startup:  enabled for next boot\n\n'
printf 'NEXT STEPS\n'
printf '1. Join this machine to your Tailscale network:\n'
printf '      sudo tailscale up\n\n'
printf '2. Run a health report if desired:\n'
printf '      sudo %s/scripts/diagnose.sh\n\n' "$INSTALL_DIR"
printf '3. Reboot to start the CareStack kiosk:\n'
printf '      sudo reboot\n\n'
printf 'If you need troubleshooting help later, run:\n'
printf '      sudo necd-support\n\n'
printf 'The first CareStack authentication is intentionally manual during the prototype phase.\n'
\n'* ]] || fail "Portal URL must be a single HTTPS URL."

printf '\nNECD Parent Kiosk Installer\n'
printf '===========================\n'
printf 'This will convert this Debian computer into a single-purpose CareStack parent kiosk.\n\n'

LOCATIONS=(village southcross schertz downtown dominion)
DISPLAY_NAMES=(Village Southcross Schertz Downtown Dominion)

if [[ -n "${NECD_LOCATION:-}" ]]; then
  LOCATION="${NECD_LOCATION,,}"
else
  echo "Choose this kiosk's office:"
  for i in "${!LOCATIONS[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${DISPLAY_NAMES[$i]}"
  done
  while true; do
    read -r -p "Location [1-${#LOCATIONS[@]}]: " choice
    if [[ "$choice" =~ ^[1-5]$ ]]; then
      LOCATION="${LOCATIONS[$((choice-1))]}"
      break
    fi
    echo "Please enter a number from 1 to ${#LOCATIONS[@]}."
  done
fi

valid_location=false
for item in "${LOCATIONS[@]}"; do
  [[ "$LOCATION" == "$item" ]] && valid_location=true
done
$valid_location || fail "Unknown location: $LOCATION"

if [[ -n "${NECD_STATION:-}" ]]; then
  STATION="$NECD_STATION"
else
  read -r -p "Station number [1]: " STATION
  STATION="${STATION:-1}"
fi
[[ "$STATION" =~ ^[0-9]+$ ]] || fail "Station number must be numeric."
(( STATION >= 1 && STATION <= 99 )) || fail "Station number must be between 1 and 99."
STATION_PADDED="$(printf '%02d' "$STATION")"
HOSTNAME_NEW="${LOCATION}-kiosk-${STATION_PADDED}"

printf '\nConfiguration\n-------------\n'
printf 'Location:  %s\n' "$LOCATION"
printf 'Station:   %s\n' "$STATION_PADDED"
printf 'Hostname:  %s\n' "$HOSTNAME_NEW"
printf 'CareStack: %s\n' "$CARESTACK_URL"

if [[ "${NECD_ASSUME_YES:-0}" != "1" ]]; then
  read -r -p "Proceed with installation? [Y/n]: " confirm
  case "${confirm:-Y}" in
    Y|y|yes|YES) ;;
    *) echo "Installation cancelled."; exit 0 ;;
  esac
fi

log "Updating Debian package metadata"
export DEBIAN_FRONTEND=noninteractive
apt-get update

log "Installing kiosk and administration packages"
apt-get install -y \
  cage \
  greetd \
  chromium \
  ca-certificates \
  curl \
  wget \
  git \
  openssh-server \
  dbus-user-session \
  libpam-systemd \
  pciutils \
  usbutils

log "Installing Tailscale"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "Tailscale is already installed."
fi

log "Creating unprivileged kiosk account"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$KIOSK_USER"
fi
passwd -l "$KIOSK_USER" >/dev/null 2>&1 || true
for group in video render input; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$KIOSK_USER"
  fi
done

log "Installing NECD kiosk files"
mkdir -p "$INSTALL_DIR"
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  cp -a "$SCRIPT_DIR"/. "$INSTALL_DIR"/
fi
chown -R root:root "$INSTALL_DIR"
find "$INSTALL_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "$INSTALL_DIR/install.sh" "$INSTALL_DIR/update.sh"
install -m 0755 "$INSTALL_DIR/scripts/necd-support.sh" /usr/local/bin/necd-support

log "Writing device configuration"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/device.conf" <<EOF
DEVICE_TYPE=parent-kiosk
LOCATION=$LOCATION
STATION=$STATION_PADDED
HOSTNAME=$HOSTNAME_NEW
CARESTACK_URL=$CARESTACK_URL
EOF
chmod 0644 "$CONFIG_DIR/device.conf"
hostnamectl set-hostname "$HOSTNAME_NEW"

log "Installing managed Chromium policies"
mkdir -p /etc/chromium/policies/managed
install -m 0644 "$INSTALL_DIR/chrome/necd-kiosk.json" \
  /etc/chromium/policies/managed/necd-kiosk.json

log "Configuring automatic kiosk session"
AGREETY_BIN="$(command -v agreety || true)"
[[ -n "$AGREETY_BIN" ]] || fail "greetd installed but agreety was not found."
cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "$AGREETY_BIN --cmd /bin/bash"
user = "greeter"

[initial_session]
command = "$INSTALL_DIR/scripts/kiosk-session.sh"
user = "$KIOSK_USER"
EOF
chmod 0644 /etc/greetd/config.toml

log "Configuring services"
systemctl enable ssh.service
systemctl enable tailscaled.service
systemctl enable greetd.service
systemctl set-default graphical.target

# A kiosk should not enter system sleep/hibernate during office hours.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

log "Installation checks"
chromium_version="$(chromium --version 2>/dev/null || echo MISSING)"
cage_version="$(cage --version 2>/dev/null | head -n1 || echo MISSING)"

printf '\nNECD kiosk installation complete\n'
printf '================================\n'
printf 'Hostname:       %s\n' "$HOSTNAME_NEW"
printf 'Location:       %s\n' "$LOCATION"
printf 'Station:        %s\n' "$STATION_PADDED"
printf 'Chromium:       %s\n' "$chromium_version"
printf 'Cage:           %s\n' "$cage_version"
printf 'SSH:            installed/enabled\n'
printf 'Tailscale:      installed; authorization may still be required\n'
printf 'Kiosk startup:  enabled for next boot\n\n'
printf 'NEXT STEPS\n'
printf '1. Join this machine to your Tailscale network:\n'
printf '      sudo tailscale up\n\n'
printf '2. Run a health report if desired:\n'
printf '      sudo %s/scripts/diagnose.sh\n\n' "$INSTALL_DIR"
printf '3. Reboot to start the CareStack kiosk:\n'
printf '      sudo reboot\n\n'
printf 'If you need troubleshooting help later, run:\n'
printf '      sudo necd-support\n\n'
printf 'The first CareStack authentication is intentionally manual during the prototype phase.\n'
; then
  fail "Existing kiosk account has privileged groups. Use a clean dedicated account."
fi
passwd -l "$KIOSK_USER" >/dev/null
chmod 0700 "/home/$KIOSK_USER"
for group in video render input; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$KIOSK_USER"
  fi
done

log "Installing NECD kiosk files"
mkdir -p "$INSTALL_DIR"
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  cp -a "$SCRIPT_DIR"/. "$INSTALL_DIR"/
fi
chown -R root:root "$INSTALL_DIR"
find "$INSTALL_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "$INSTALL_DIR/install.sh" "$INSTALL_DIR/update.sh"
install -m 0755 "$INSTALL_DIR/scripts/necd-support.sh" /usr/local/bin/necd-support

log "Writing device configuration"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/device.conf" <<EOF
DEVICE_TYPE=parent-kiosk
LOCATION=$LOCATION
STATION=$STATION_PADDED
HOSTNAME=$HOSTNAME_NEW
CARESTACK_URL=$CARESTACK_URL
EOF
chmod 0644 "$CONFIG_DIR/device.conf"
hostnamectl set-hostname "$HOSTNAME_NEW"

log "Installing managed Chromium policies"
mkdir -p /etc/chromium/policies/managed
install -m 0644 "$INSTALL_DIR/chrome/necd-kiosk.json" \
  /etc/chromium/policies/managed/necd-kiosk.json

log "Configuring automatic kiosk session"
AGREETY_BIN="$(command -v agreety || true)"
[[ -n "$AGREETY_BIN" ]] || fail "greetd installed but agreety was not found."
cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "$AGREETY_BIN --cmd /bin/bash"
user = "greeter"

[initial_session]
command = "$INSTALL_DIR/scripts/kiosk-session.sh"
user = "$KIOSK_USER"
EOF
chmod 0644 /etc/greetd/config.toml

log "Configuring services"
systemctl enable ssh.service
systemctl enable tailscaled.service
systemctl enable greetd.service
systemctl set-default graphical.target

# A kiosk should not enter system sleep/hibernate during office hours.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

log "Installation checks"
chromium_version="$(chromium --version 2>/dev/null || echo MISSING)"
cage_version="$(cage --version 2>/dev/null | head -n1 || echo MISSING)"

printf '\nNECD kiosk installation complete\n'
printf '================================\n'
printf 'Hostname:       %s\n' "$HOSTNAME_NEW"
printf 'Location:       %s\n' "$LOCATION"
printf 'Station:        %s\n' "$STATION_PADDED"
printf 'Chromium:       %s\n' "$chromium_version"
printf 'Cage:           %s\n' "$cage_version"
printf 'SSH:            installed/enabled\n'
printf 'Tailscale:      installed; authorization may still be required\n'
printf 'Kiosk startup:  enabled for next boot\n\n'
printf 'NEXT STEPS\n'
printf '1. Join this machine to your Tailscale network:\n'
printf '      sudo tailscale up\n\n'
printf '2. Run a health report if desired:\n'
printf '      sudo %s/scripts/diagnose.sh\n\n' "$INSTALL_DIR"
printf '3. Reboot to start the CareStack kiosk:\n'
printf '      sudo reboot\n\n'
printf 'If you need troubleshooting help later, run:\n'
printf '      sudo necd-support\n\n'
printf 'The first CareStack authentication is intentionally manual during the prototype phase.\n'
\n'* ]] || fail "Portal URL must be a single HTTPS URL."

printf '\nNECD Parent Kiosk Installer\n'
printf '===========================\n'
printf 'This will convert this Debian computer into a single-purpose CareStack parent kiosk.\n\n'

LOCATIONS=(village southcross schertz downtown dominion)
DISPLAY_NAMES=(Village Southcross Schertz Downtown Dominion)

if [[ -n "${NECD_LOCATION:-}" ]]; then
  LOCATION="${NECD_LOCATION,,}"
else
  echo "Choose this kiosk's office:"
  for i in "${!LOCATIONS[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${DISPLAY_NAMES[$i]}"
  done
  while true; do
    read -r -p "Location [1-${#LOCATIONS[@]}]: " choice
    if [[ "$choice" =~ ^[1-5]$ ]]; then
      LOCATION="${LOCATIONS[$((choice-1))]}"
      break
    fi
    echo "Please enter a number from 1 to ${#LOCATIONS[@]}."
  done
fi

valid_location=false
for item in "${LOCATIONS[@]}"; do
  [[ "$LOCATION" == "$item" ]] && valid_location=true
done
$valid_location || fail "Unknown location: $LOCATION"

if [[ -n "${NECD_STATION:-}" ]]; then
  STATION="$NECD_STATION"
else
  read -r -p "Station number [1]: " STATION
  STATION="${STATION:-1}"
fi
[[ "$STATION" =~ ^[0-9]+$ ]] || fail "Station number must be numeric."
(( STATION >= 1 && STATION <= 99 )) || fail "Station number must be between 1 and 99."
STATION_PADDED="$(printf '%02d' "$STATION")"
HOSTNAME_NEW="${LOCATION}-kiosk-${STATION_PADDED}"

printf '\nConfiguration\n-------------\n'
printf 'Location:  %s\n' "$LOCATION"
printf 'Station:   %s\n' "$STATION_PADDED"
printf 'Hostname:  %s\n' "$HOSTNAME_NEW"
printf 'CareStack: %s\n' "$CARESTACK_URL"

if [[ "${NECD_ASSUME_YES:-0}" != "1" ]]; then
  read -r -p "Proceed with installation? [Y/n]: " confirm
  case "${confirm:-Y}" in
    Y|y|yes|YES) ;;
    *) echo "Installation cancelled."; exit 0 ;;
  esac
fi

log "Updating Debian package metadata"
export DEBIAN_FRONTEND=noninteractive
apt-get update

log "Installing kiosk and administration packages"
apt-get install -y \
  cage \
  greetd \
  chromium \
  ca-certificates \
  curl \
  wget \
  git \
  openssh-server \
  dbus-user-session \
  libpam-systemd \
  pciutils \
  usbutils

log "Installing Tailscale"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "Tailscale is already installed."
fi

log "Creating unprivileged kiosk account"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$KIOSK_USER"
fi
passwd -l "$KIOSK_USER" >/dev/null 2>&1 || true
for group in video render input; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$KIOSK_USER"
  fi
done

log "Installing NECD kiosk files"
mkdir -p "$INSTALL_DIR"
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  cp -a "$SCRIPT_DIR"/. "$INSTALL_DIR"/
fi
chown -R root:root "$INSTALL_DIR"
find "$INSTALL_DIR/scripts" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "$INSTALL_DIR/install.sh" "$INSTALL_DIR/update.sh"
install -m 0755 "$INSTALL_DIR/scripts/necd-support.sh" /usr/local/bin/necd-support

log "Writing device configuration"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/device.conf" <<EOF
DEVICE_TYPE=parent-kiosk
LOCATION=$LOCATION
STATION=$STATION_PADDED
HOSTNAME=$HOSTNAME_NEW
CARESTACK_URL=$CARESTACK_URL
EOF
chmod 0644 "$CONFIG_DIR/device.conf"
hostnamectl set-hostname "$HOSTNAME_NEW"

log "Installing managed Chromium policies"
mkdir -p /etc/chromium/policies/managed
install -m 0644 "$INSTALL_DIR/chrome/necd-kiosk.json" \
  /etc/chromium/policies/managed/necd-kiosk.json

log "Configuring automatic kiosk session"
AGREETY_BIN="$(command -v agreety || true)"
[[ -n "$AGREETY_BIN" ]] || fail "greetd installed but agreety was not found."
cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "$AGREETY_BIN --cmd /bin/bash"
user = "greeter"

[initial_session]
command = "$INSTALL_DIR/scripts/kiosk-session.sh"
user = "$KIOSK_USER"
EOF
chmod 0644 /etc/greetd/config.toml

log "Configuring services"
systemctl enable ssh.service
systemctl enable tailscaled.service
systemctl enable greetd.service
systemctl set-default graphical.target

# A kiosk should not enter system sleep/hibernate during office hours.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

log "Installation checks"
chromium_version="$(chromium --version 2>/dev/null || echo MISSING)"
cage_version="$(cage --version 2>/dev/null | head -n1 || echo MISSING)"

printf '\nNECD kiosk installation complete\n'
printf '================================\n'
printf 'Hostname:       %s\n' "$HOSTNAME_NEW"
printf 'Location:       %s\n' "$LOCATION"
printf 'Station:        %s\n' "$STATION_PADDED"
printf 'Chromium:       %s\n' "$chromium_version"
printf 'Cage:           %s\n' "$cage_version"
printf 'SSH:            installed/enabled\n'
printf 'Tailscale:      installed; authorization may still be required\n'
printf 'Kiosk startup:  enabled for next boot\n\n'
printf 'NEXT STEPS\n'
printf '1. Join this machine to your Tailscale network:\n'
printf '      sudo tailscale up\n\n'
printf '2. Run a health report if desired:\n'
printf '      sudo %s/scripts/diagnose.sh\n\n' "$INSTALL_DIR"
printf '3. Reboot to start the CareStack kiosk:\n'
printf '      sudo reboot\n\n'
printf 'If you need troubleshooting help later, run:\n'
printf '      sudo necd-support\n\n'
printf 'The first CareStack authentication is intentionally manual during the prototype phase.\n'
