# DMS Greeter

<div align="center">
  <a href="https://danklinux.com">
    <img src="assets/danklogo.svg" alt="DMS Greeter" width="200">
  </a>

### A greetd login screen with the Dank Material aesthetic

Built with [Quickshell](https://quickshell.org/) and [Go](https://go.dev/)

[![Documentation](https://img.shields.io/badge/docs-danklinux.com-9ccbfb?style=for-the-badge&labelColor=101418)](https://danklinux.com/docs/dankgreeter)
[![GitHub stars](https://img.shields.io/github/stars/AvengeMedia/dank-greeter?style=for-the-badge&labelColor=101418&color=ffd700)](https://github.com/AvengeMedia/dank-greeter/stargazers)
[![GitHub License](https://img.shields.io/github/license/AvengeMedia/dank-greeter?style=for-the-badge&labelColor=101418&color=b9c8da)](https://github.com/AvengeMedia/dank-greeter/blob/master/LICENSE)
[![AUR version (git)](<https://img.shields.io/aur/version/greetd-dms-greeter-git?style=for-the-badge&labelColor=101418&color=9ccbfb&label=AUR%20(git)>)](https://aur.archlinux.org/packages/greetd-dms-greeter-git)
[![Discord](https://img.shields.io/badge/discord-join?style=for-the-badge&logo=discord&logoColor=ffffff&label=discord&labelColor=101418&color=5865f2)](https://discord.gg/ppWTpKmPgT)
[![Ko-Fi donate](https://img.shields.io/badge/donate-kofi?style=for-the-badge&logo=ko-fi&logoColor=ffffff&label=ko-fi&labelColor=101418&color=f16061&link=https%3A%2F%2Fko-fi.com%2Fdanklinux)](https://ko-fi.com/danklinux)

</div>

DMS Greeter is a login screen for [greetd](https://github.com/kennylevinsen/greetd) that looks and behaves like the [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) lock screen. It ships as a single `dms-greeter` binary with the Quickshell UI embedded, runs under niri, Hyprland, Sway, Scroll, Miracle WM, labwc, or MangoWC, and syncs your DMS theme, wallpaper, and settings so the login screen matches your desktop.

## Repository Structure

This is a monorepo containing both the greeter interface and the core backend:

```
dank-greeter/
├── quickshell/         # QML-based greeter interface
│   ├── Modules/Greetd/ # Login screen, user picker, session selection
│   ├── Services/       # Read-only status (network, battery, audio, weather)
│   ├── Widgets/        # Dank UI controls
│   ├── Common/         # Shared resources, themes, and i18n
│   ├── DankCommon/     # → symlink into the dank-qml-common submodule
│   └── translations/   # POEditor-managed string catalogs
├── dank-qml-common/    # Shared DMS widget library (git submodule)
├── core/               # Go backend and CLI
│   ├── cmd/dms-greeter/# CLI entrypoint and greeter launcher
│   └── internal/       # Compositor launcher, greetd config, sync, PAM
├── distro/             # Distribution packaging + NixOS module
├── assets/             # sysusers/tmpfiles, AppArmor profile, sample configs
└── Makefile            # Build, install, and dev targets
```

## Installation

### Arch Linux (AUR)

```bash
yay -S greetd-dms-greeter-git
```

### Debian / openSUSE

Official packages are available from the [DankLinux OBS repository](https://software.opensuse.org/download/package?package=dms-greeter&project=home%3AAvengeMedia%3Adanklinux). Add the repo for your distribution, then install **`dms-greeter`** (stable) or **`dms-greeter-git`** (master; Conflicts with stable):

```bash
# Debian 13
sudo apt install dms-greeter
# sudo apt install dms-greeter-git

# openSUSE Tumbleweed
zypper install dms-greeter
# zypper install dms-greeter-git
```

Ubuntu uses the same package names from [`ppa:avengemedia/danklinux`](https://launchpad.net/~avengemedia/+archive/ubuntu/danklinux). See the [Installation guide](https://danklinux.com/docs/dankgreeter/installation) for full repository setup.

### Fedora / RHEL / Rocky / Alma

```bash
sudo dnf copr enable avengemedia/danklinux
sudo dnf install dms-greeter
```

For the latest development build from `master` (Conflicts with the stable package):

```bash
sudo dnf copr enable avengemedia/danklinux
sudo dnf install dms-greeter-git
```

### Void Linux

```bash
echo 'repository=https://void.danklinux.com/dms/current' | sudo tee /etc/xbps.d/dms.conf
sudo xbps-install -S dms-greeter
# sudo xbps-install -S dms-greeter-git   # master snapshots; Conflicts with stable
```

The packages create the greeter user (via `systemd-sysusers` for atomic/immutable compatibility, with package script fallback), set up directories and permissions, and apply SELinux contexts where relevant.

After installing from any package:

```bash
dms-greeter enable   # point greetd at dms-greeter
dms-greeter sync     # sync your DMS theme to the login screen
```

Or run `dms-greeter install` for interactive setup - it installs greetd where needed and writes `/etc/greetd/config.toml` for you.

### From Source

```bash
git clone --recurse-submodules https://github.com/AvengeMedia/dank-greeter.git
cd dank-greeter
make build
sudo make install
```

Already cloned without submodules? Run `git submodule update --init` first -
the shared widget library ([dank-qml-common](https://github.com/AvengeMedia/dank-qml-common))
is vendored as a submodule and the build fails without it.

Then create the greeter user and cache directory if your setup doesn't have them:

```bash
sudo groupadd -r greeter
sudo useradd -r -g greeter -d /var/lib/greeter -s /bin/bash -c "System Greeter" greeter
sudo mkdir -p /var/lib/greeter /var/cache/dms-greeter
sudo chown greeter:greeter /var/lib/greeter /var/cache/dms-greeter
sudo chmod 2770 /var/cache/dms-greeter
```

And finish with `dms-greeter enable && dms-greeter sync`, or write `/etc/greetd/config.toml` yourself (see Usage).

At launch the embedded UI is unpacked read-only under the greeter cache
directory and verified against the binary on every start, so editing the
unpacked files has no effect. To run a modified copy of the UI, point
dms-greeter at any directory containing a `shell.qml` with `-c <dir>` or the
`DMS_GREETER_SHELL_DIR` environment variable - there is no implicit filesystem
lookup otherwise.

### NixOS

Add the repo to your flake inputs, then:

```nix
imports = [
  inputs.dank-greeter.nixosModules.default
];

programs.dms-greeter = {
  enable = true;
  compositor.name = "niri"; # or hyprland, sway, labwc, mango, scroll, miracle
  configHome = "/home/user"; # copies that user's DMS settings (and wallpaper) into the greeter data directory before greetd starts
};
```

### Requirements

- [greetd](https://github.com/kennylevinsen/greetd)
- [Quickshell](https://quickshell.org) (`qs`)
- One of the supported compositors
- Go 1.26+ (build only - the binary is pure Go, no CGO)

## Features

**DMS Sync**
`dms-greeter sync` copies your DankMaterialShell theme, wallpaper, and settings
into the greeter cache, so the login screen matches your desktop. Greeter
options live in DMS under **Settings → Greeter** - the greeter itself only
reads the synced files.

**Multi User**
Log in as any system user, with per-user themes and profile images in the user
picker.

**Multiple Compositors**
One binary launches the greeter under niri, Hyprland, Sway, Scroll,
Miracle WM, labwc, or MangoWC, generating the compositor config on the fly.

**Session Memory**
Remembers the last selected session and user. Disable via the
`greeterRememberLastSession` and `greeterRememberLastUser` settings, or the
`--no-save-session` / `--no-save-username` flags.

**Fingerprint & Security Keys**
Optional fingerprint (`pam_fprintd`) and U2F (`pam_u2f`) login, managed
through `/etc/pam.d/greetd`. Existing custom PAM configuration is respected.

**Localized**
User-facing strings are translatable and managed through POEditor.

## Usage

greetd runs the greeter through `/etc/greetd/config.toml`:

```toml
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "/usr/bin/dms-greeter --command niri"
```

The launcher takes care of the compositor side:

```bash
dms-greeter --command niri
dms-greeter --command hyprland
dms-greeter --command sway
dms-greeter --command mangowc
dms-greeter --command niri -C /path/to/custom-niri.kdl
dms-greeter --command niri --remember-last-user false --remember-last-session false
```

## Configuration

### Compositor

Only niri has a generated greeter config path managed by `dms-greeter sync`:

- niri: `dms-greeter sync` writes the generated greeter config to `/etc/greetd/niri/config.kdl`. Add local manual tweaks in `/etc/greetd/niri_overrides.kdl`.
- Other compositors use a launcher-generated config by default. For a custom compositor config, add `-C /path/to/config` to the `dms-greeter` command in `/etc/greetd/config.toml`.

### Personalization

The greeter is personalized with wallpapers, themes, weather, and clock formats the same way as DMS itself.

**Single user:** run `dms-greeter sync` and you're done.

**Multi-user systems:** one **main admin** runs full sync once to set up greetd and the shared cache (`dms-greeter sync`, or `dms-greeter sync --local` when developing from a checkout). **Every other account** - including other admins - should only run:

```bash
dms-greeter sync --profile
```

Before that, an administrator must add each user to the `greeter` group in DMS **Settings → Users** (greeter toggle) or with `sudo usermod -aG greeter <username>`. Each added user must log out and back in before `--profile` will work.

Per-user settings are stored under `/var/cache/dms-greeter/users/<username>/` for the login picker; the root cache remains the default fallback and is owned by whoever ran full sync.

**Manual method:** if you want greeter settings to always mirror your shell:

```bash
# Add yourself to the greeter group
sudo usermod -aG greeter $USER

# Set ACLs to allow greeter user to traverse your home directory
setfacl -m u:greeter:x ~ ~/.config ~/.local ~/.cache ~/.local/state

# Set group permissions on DMS directories
sudo chgrp -R greeter ~/.config/DankMaterialShell ~/.local/state/DankMaterialShell ~/.cache/quickshell
sudo chmod -R g+rX ~/.config/DankMaterialShell ~/.local/state/DankMaterialShell ~/.cache/quickshell

# Create symlinks for theme files
sudo ln -sf ~/.config/DankMaterialShell/settings.json /var/cache/dms-greeter/settings.json
sudo ln -sf ~/.local/state/DankMaterialShell/session.json /var/cache/dms-greeter/session.json
sudo ln -sf ~/.cache/DankMaterialShell/dms-colors.json /var/cache/dms-greeter/colors.json

# Logout and login for group membership to take effect
```

The cache directory location can be overridden with `--cache-dir` (default `/var/cache/dms-greeter`). It should be owned by `<greeter-user>:<greeter-group>` with `2770` permissions; if the greeter user doesn't exist yet, sync falls back to `root:<greeter-group>`.

### Fingerprint authentication

Install your distribution's fingerprint service and PAM integration before enabling it. On Fedora the native stack is:

```bash
sudo dnf install fprintd fprintd-pam
fprintd-enroll
```

After enrollment, enable fingerprint login in DMS **Settings → Greeter**. The toggle applies the PAM configuration on the next `dms-greeter sync`; use `dms-greeter sync --auth` to apply authentication configuration alone.

greetd tries fingerprint and password sequentially. Managed PAM allows two scans for up to ten seconds before password fallback. Existing distro PAM policy takes precedence, so fallback timing can differ.

Verify enrollment with `fprintd-list "$USER"`; pass a token such as `fprintd-enroll -f right-thumb` to enroll a specific finger. Security keys similarly require `pam_u2f` setup and key registration before enabling the login toggle.

If `fprintd-enroll` reports **No devices available**, check the [libfprint supported devices list](https://fprint.freedesktop.org/supported-devices.html). Some Validity/Synaptics readers are not supported by the native stack regardless of distribution; the [open-fprintd](https://github.com/uunicorn/open-fprintd) service with the [python-validity](https://github.com/uunicorn/python-validity) driver may work instead. Don't run the stock `fprintd` daemon alongside its replacement.

## Development

```bash
make dev     # fast build without the embedded UI
make run     # preview the greeter UI in your current session
make build   # release build with the UI embedded
make test    # run the Go test suite
```
