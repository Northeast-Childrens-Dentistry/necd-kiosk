# NECD Patient Kiosk

Repurpose NECD all-in-one computers as dedicated CareStack check-in and forms stations. Debian boots directly into fullscreen Patient Connect; IT administers each station over Tailscale and SSH.

**Status: pilot implementation, not approved for unattended patient use.** This revision has not been boot-tested on NECD hardware. Complete the acceptance checklist below before rollout. The GitHub validation workflow checks shell syntax and JSON, not hardware or CareStack behavior.

## How it works

Power on → Debian 13 → greetd automatic kiosk session → Cage → Chromium → CareStack Patient Connect.

Staff authenticate, choose **Kiosk Mode**, select the office, and confirm the patient welcome screen. Browser launch is automatic; CareStack authentication is manual. No credentials, OTP bypass, or automatic staff login are implemented. The location chosen in the installer labels the device; it does **not** select the location inside CareStack.

This continues the existing NECD kiosk project. It follows SAPR-funbox's minimal Debian appliance approach but retains the existing Cage/Wayland stack. It does not install the karaoke, audio, or rental software.

## Hardware and operating system

- Debian **13 / trixie**, amd64; minimal install with SSH server and standard system utilities, no desktop.
- 4 GB RAM and 20 GB free disk minimum; 8 GB RAM and SSD preferred.
- Healthy existing HDDs are acceptable for the pilot.
- Ethernet preferred. Configure Wi-Fi during Debian installation if needed; this installer does not change network ownership or provide a parent-accessible network chooser.
- Test graphics, touchscreen, screen orientation and signatures on every hardware model.
- **Provide a keyboard and mouse for the pilot.** Touch input may work, but no on-screen keyboard is installed; touchscreen-only deployment is not ready until text entry is solved and tested.
- Back up any existing files before IT installs Debian. Installing Debian can erase the old OS.

## Installation

Create a separate named IT administrator with sudo access during Debian setup. Install sudo as root if the installer did not provide it. Keep this account separate from the locked, unprivileged `kiosk` account.

This repository is **private**. Clone using the IT administrator's authorized SSH key or credential helper; an anonymous clone will fail. Never embed a token in the Git URL or store Git credentials in the kiosk account.

```bash
sudo apt update
sudo apt install -y git sudo
git clone git@github.com:kevcops/necd-kiosk.git
cd necd-kiosk
# During the pilot, select the review branch:
git switch codex/it-handoff-2026-10
git log -1 --oneline
# Review the revision with IT, then:
sudo bash install.sh
sudo tailscale up
sudo reboot
```

Use `bash install.sh`: source files in Git need not have executable bits.

Installer prompts for office and station 1–99. Supported identifiers:

| Office | Identifier | Example hostname |
| --- | --- | --- |
| Village Drive / Northeast | village | village-kiosk-01 |
| Southcross | southcross | southcross-kiosk-01 |
| Schertz | schertz | schertz-kiosk-01 |
| Downtown | downtown | downtown-kiosk-01 |
| Dominion Crossing | dominion | dominion-kiosk-01 |
| Northern Oaks | northern-oaks | northern-oaks-kiosk-01 |

For a repeatable installation:

```bash
sudo env NECD_LOCATION=schertz NECD_STATION=01 NECD_ASSUME_YES=1 bash install.sh
```

The installer installs Debian Chromium, Cage, greetd, OpenSSH and Tailscale; creates the kiosk account; writes root-owned configuration; enables boot startup; disables system sleep; and enables unattended Debian updates without automatic reboot. It does not enroll Tailscale, change SSH authentication, create firewall rules, configure the tailnet's access policy, or change firmware power settings.

## CareStack setup and daily opening

Default portal:

<https://patientportal-mw.carestack.com/?dn=necdsa#/patient-connect>

Confirm this tenant URL with NECD before using live patient data. Use Patient Connect, not the staff clinical application.

1. Staff sign in with an account approved for kiosk use.
2. Choose Kiosk Mode and the correct office.
3. Confirm the parent-facing welcome screen before handing over.
4. Test check-in and forms against a designated test patient.
5. Confirm completed and abandoned sessions do not expose the previous patient's details.

CareStack controls application logout and patient-session separation. Its public FAQ describes automatic logout after check-in, but IT must validate actual behavior for NECD's tenant, forms, abandonment and browser Back actions. Do not treat a local browser restart timer as patient logout. No timer that interrupts active forms is installed.

Reauthenticate after every browser restart, reboot or expired CareStack session. Earlier planning mentioned a 24-hour limit; the current tenant's exact timeout remains unverified.

To override the URL, rerun the installer with a quoted `NECD_CARESTACK_URL` HTTPS value. Existing station identity is retained. The URL is stored in `/etc/necd-kiosk/device.conf` and read by the launcher. It must not contain a password, patient identifier or authentication token.

## Remote support

Enroll each device interactively with `sudo tailscale up`. Use organization-owned enrollment and restrict tailnet access to authorized IT users/devices and the required kiosk SSH port. This project uses **ordinary OpenSSH over Tailscale**, not Tailscale SSH, VNC or screen sharing.

```bash
ssh IT_USERNAME@schertz-kiosk-01
sudo /opt/necd-kiosk/scripts/diagnose.sh
sudo /opt/necd-kiosk/scripts/reset-kiosk.sh
sudo necd-support
```

MagicDNS must be enabled for hostname connections; otherwise use the device's Tailscale IP. Set up and test administrator SSH keys. After confirming a second successful key-authenticated session, IT should disable SSH password/root login under its standard policy. Restrict LAN SSH at the network/host firewall as appropriate; installing Tailscale alone does not hide the LAN SSH listener. Do not expose SSH through router port forwarding.

Restarting closes active forms and clears the browser session. Coordinate with reception first. Staff must sign in again afterward.

`necd-support` creates a minimal private archive, owned by the invoking sudo administrator, and prints a copy command. It excludes journals, browser data, configuration and network inventory. The interactive `diagnose.sh` is more detailed and can show configuration/logs: review it before sharing; do not paste it into public issues.

## Browser controls and data

- Kiosk account has no sudo role and its password is locked.
- Chromium sandbox remains enabled.
- Password saving, autofill, sync, downloads, printing, extensions and developer tools are restricted.
- Top-level navigation is limited to HTTPS CareStack domains. External identity providers or workflows may require a narrowly scoped addition to `URLAllowlist`; validate login and all forms before deployment. URL policies do not replace a network firewall.
- Browser profile resides in the user's runtime tmpfs and is recreated on each browser launch. Cookies, login state and unfinished work are lost on restart.
- This does not clear an abandoned patient's screen while the browser remains open. CareStack session controls and staff supervision are required.
- Runtime memory can reach swap. IT must configure encrypted storage/swap or disable swap as appropriate for the device and validate memory capacity. Existing disk browser profiles from older prototypes are not automatically deleted; retire them through IT's data-handling procedure.
- Journals are configured to be volatile on the next journald restart/boot. Older persistent journals are not automatically purged.
- Kiosk mode is not a complete physical security boundary. Keep the station supervised, secure firmware/external boot and validate keyboard escape paths.

## Updates and rollback

Debian security updates use unattended-upgrades; reboots are manual and browsers must be restarted during a maintenance window to load new browser packages. Tailscale/package maintenance remains IT's responsibility; confirm repository origin coverage in unattended-upgrades.

Application code is never pulled unattended. Fetch in the administrator's checkout, review a full commit SHA, and apply during downtime:

```bash
cd ~/necd-kiosk
git fetch origin
git checkout FULL_APPROVED_COMMIT_SHA
sudo bash update.sh "$PWD" FULL_APPROVED_COMMIT_SHA
```

Replace the placeholder with the actual 40-character approved SHA. The updater rejects dirty checkouts and SHA mismatches, exports committed files, reapplies the installer (preserving station configuration), records the revision and restarts greetd. No Git credentials are copied into the runtime export. Installation is not transactional: retain a system backup and a known-good revision.

To roll back application files, check out the previous approved SHA and run the same update command with that SHA. This does not downgrade OS packages or reverse every system configuration change. For failed provisioning or a major OS change, use the IT backup or reinstall Debian.

## Acceptance checklist — one station first

- [ ] Cold boot three times; portal appears without Linux login.
- [ ] Correct hostname, office and station recorded in asset inventory.
- [ ] Keyboard/mouse and touch/signature input work; no required input is inaccessible.
- [ ] CareStack login, Kiosk Mode and correct office selected.
- [ ] Check-in updates the expected appointment and signed forms arrive correctly.
- [ ] Completed and abandoned sessions, Back, refresh and browser restart do not expose another patient's data.
- [ ] Portal allowlist permits required login/form flows and blocks unrelated navigation.
- [ ] Browser exit recovers automatically; staff can reauthenticate.
- [ ] Network disconnect/reconnect and power failure recovery tested.
- [ ] IT can SSH over Tailscale; unauthorized tailnet access denied.
- [ ] Test support archive permissions and administrator download.
- [ ] Review disk/swap protection, physical escape paths and old prototype data.
- [ ] Test approved update and application rollback.
- [ ] Observe one full clinic day; reception and IT sign off before replication.

A browser hang or network error page does not necessarily exit Chromium; IT may need to restart the session. No DOM health watcher, cloud fleet dashboard, unattended credential entry or remote desktop is included.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Black screen | Check greetd logs locally/through IT; verify GPU/Wayland compatibility. Do not disable Chromium sandbox. |
| Portal blocked | Check network, clock and required CareStack/identity-provider domains; review managed policy with IT. |
| Missing forms/location | Check CareStack permissions/configuration; device hostname does not set application location. |
| Login returns after reboot | Expected: the temporary browser profile was cleared. |
| Tailscale offline | Check network, service status, enrollment/key expiry and tailnet policy. |
| Touch keyboard absent | Use physical keyboard; no on-screen keyboard is included. |
| Private Git clone denied | Authorize IT's GitHub identity; do not make the repository public as a workaround. |

## Files and handoff

- `install.sh`: Debian provisioning.
- `scripts/kiosk-session.sh`: compositor recovery loop.
- `scripts/start-kiosk.sh`: temporary-profile browser launcher.
- `chrome/necd-kiosk.json`: managed Chromium policy.
- `update.sh`: reviewed-revision deployment.
- `docs/IT-HANDOFF.html`: printable two-page IT sheet. Download and open locally, then Print → Save as PDF (Letter, background graphics).
- `.github/workflows/validate.yml`: static checks.

The handoff uses cream surfaces, rounded black outlines and friendly typography inspired by NECD's established direction. Exact brand tokens/logo assets were unavailable for this revision; accent colors are provisional and no official logo was reconstructed.

## References

- [SAPR-funbox reference](https://github.com/kevcops/SAPR-funbox)
- [Debian installation](https://www.debian.org/releases/trixie/installmanual)
- [Official Tailscale Debian packages](https://pkgs.tailscale.com/stable/)
- [CareStack Patient Kiosk](https://carestack.com/dental-software/features/patient-kiosk)
- [CareStack FAQ](https://carestack.com/dental-software/faq)
