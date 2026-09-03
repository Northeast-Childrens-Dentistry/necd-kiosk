# NECD Kiosk

Lightweight Debian-based patient kiosk configuration for Northeast Children's Dentistry.

The goal is to repurpose older office PCs as single-purpose CareStack Patient Connect kiosks.

## Target stack

- Debian Stable (minimal install)
- Cage Wayland kiosk compositor
- Google Chrome
- CareStack Patient Connect
- Tailscale for remote administration
- OpenSSH

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

The installer asks for the office location and station number, creates the kiosk account, configures automatic kiosk startup, installs Chrome/Cage/Tailscale, and configures the machine hostname.

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
- Browser password saving and autofill are disabled through managed Chrome policies.
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

This project is under active development. The first goal is to validate Debian + Cage + Chrome + CareStack on an HP Omni 120-class computer with an Intel Core i3-2120, 6 GB RAM, and its existing mechanical hard drive.
