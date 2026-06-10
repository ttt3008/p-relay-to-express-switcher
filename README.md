# P- Relay to Express Switcher

A small macOS menu bar app for people who use ExpressVPN but also want iCloud Private Relay to work when ExpressVPN is not in use.

## Who this helps

This may help if:

- You use ExpressVPN on macOS.
- iCloud Private Relay becomes unavailable, stuck, or disabled after ExpressVPN runs.
- Quitting ExpressVPN is not enough because the ExpressVPN background daemon keeps running.
- You want a simple switch between Private Relay mode and ExpressVPN mode.

This does not make ExpressVPN and iCloud Private Relay run together. It switches between them.

## What the modes do

Private Relay mode:

- Quits ExpressVPN.
- Stops/disables the ExpressVPN background daemon.
- Lets iCloud Private Relay work normally again.

ExpressVPN mode:

- Enables/starts the ExpressVPN background daemon.
- Opens ExpressVPN.
- Private Relay may become unavailable while ExpressVPN is active.

## Install

1. Make sure ExpressVPN is installed in `/Applications`.
2. Open `P- Relay to Express Switcher Installer.dmg`.
3. Drag `P- Relay to Express Switcher.app` to Applications.
4. Open the app from Applications.
5. Approve helper tool installation when prompted.

The app is unsigned/not notarized. On first launch, macOS may require right-clicking the app and choosing Open.

## Why helper tools are required

macOS requires administrator privileges to enable or disable system LaunchDaemons. The app installs two root-owned helper commands and a narrow sudo rule for the current Mac user.

Installed helper files:

- `/usr/local/sbin/expressvpn-private-relay-mode`
- `/usr/local/sbin/expressvpn-enable-mode`
- `/etc/sudoers.d/expressvpn-private-relay-switch-<username>`

The sudo rule only allows the current user to run those two helper commands as root without a password.

## Uninstall

1. Run `Uninstall Helper Tools.app` from the DMG.
2. Delete `P- Relay to Express Switcher.app` from Applications.

The uninstaller does not remove ExpressVPN itself.

## Safety notes

- This app changes ExpressVPN LaunchDaemon state.
- It is intended for macOS users who understand the tradeoff between Private Relay mode and ExpressVPN mode.
- Do not edit the installed helper commands after installation. They are installed as root-owned files so normal users cannot modify what the passwordless sudo rule runs.
- Review the included source before installing if you are unsure.

## Current DMG checksum

See `SHA256SUMS.txt`.
