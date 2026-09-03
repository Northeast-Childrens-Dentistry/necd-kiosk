# NECD Kiosk

Lightweight Debian-based patient kiosk configuration for Northeast Children's Dentistry.

The goal is to repurpose compatible older hardware as single-purpose CareStack Patient Connect kiosks.

## System requirements

### Minimum

- 64-bit x86 processor supported by current Debian and Chromium
- 4 GB RAM
- 20 GB available storage
- Working display
- Keyboard and mouse, or touchscreen input
- Ethernet or Wi-Fi supported by Debian
- Ability to boot and install Debian Stable

### Recommended

- Intel Core i3-class processor or comparable performance
- 6 GB RAM or more
- 64 GB or more storage
- 1366×768 display or better; 1920×1080 preferred
- Wired Ethernet where practical
- SSD preferred for faster startup and updates, but a healthy HDD is acceptable

This project is intended to be hardware-agnostic. Any compatible desktop, all-in-one, laptop, mini PC, or similar x86-64 system may be used if it meets the requirements above and performs adequately with CareStack in Chromium.

## Target stack

- Debian Stable (minimal install)
- Cage Wayland kiosk compositor
- Debian Chromium
- CareStack Patient Connect
- Tailscale for remote administration
- OpenSSH

Chromium is installed directly from Debian's repositories so browser updates are handled through normal Debian package management. Google Chrome is not required.

## CareStack URL

`https://patientportal-mw.carestack.com/?dn=necdsa#/patient-connect`

## Prototype install

Install Debian with only **SSH server** and **standard system utilities**, then log in with an administrator account and run:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/kevcops/necd-kiosk.git
cd necd-kiosk
sudo ./install.sh
```

The installer asks for the office location and station number, creates the kiosk account, configures automatic kiosk startup, installs Chromium/Cage/Tailscale, and configures the kiosk hostname.

After installation, authorize Tailscale once with:

```bash
sudo tailscale up
```

Then reboot:

```bash
sudo reboot
```

## Security model

- The local `kiosk` account has no sudo access.
- Browser password saving and autofill are disabled through managed Chromium policies.
- CareStack credentials are **never stored in this repository**.
- Tailscale authentication keys are **never stored in this repository**.
- Initial CareStack login is manual during the prototype phase.
- Automated CareStack login will be added later using a dedicated least-privilege kiosk account and local protected credentials.

## Management commands

Run a local health report:

```bash
sudo /opt/necd-kiosk/scripts/diagnose.sh
```

Restart the kiosk browser session remotely over SSH:

```bash
sudo /opt/necd-kiosk/scripts/reset-kiosk.sh
```

Update the NECD kiosk code from GitHub:

```bash
sudo /opt/necd-kiosk/update.sh
```

## Prototype status

This project is under active development. The initial goal is to validate Debian + Cage + Chromium + CareStack across a range of compatible older hardware and refine the installer, remote-management workflow, and recovery behavior.
