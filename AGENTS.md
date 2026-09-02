## What is this?

dank-greeter is a greetd login screen (`dms-greeter`) that looks and behaves like the DankMaterialShell (DMS) lock screen. It is a sibling of DMS, not DMS itself. It ships as a single pure-Go binary with the Quickshell UI embedded, launches its own compositor session (niri, Hyprland, Sway, Scroll, Miracle WM, labwc, MangoWC), and reads theme, wallpaper, and settings that `dms-greeter sync` copies out of a user's DMS config into `/var/cache/dms-greeter`.

The greeter is read-only. Greeter options are edited in DMS under Settings -> Greeter and synced here. The greeter never writes back to DMS config.

## Repo Structure:

Two apps plus a shared widget submodule.

### 1- core:

Go module at `core/`, one binary `cmd/dms-greeter`. It is a cobra CLI and a greeter launcher in one:

- `cmd/dms-greeter/` - the bare `dms-greeter --command <compositor>` is what greetd runs. Subcommands: `install` (interactive greetd setup), `enable`, `sync` (with `--profile` and `--local`), `status`, `uninstall`, `version`, and the hidden `launch-session`. Also the systemd service and immutable-distro handling.
- `internal/launcher/` - starts the compositor with a generated config, cursor, and logging, then runs quickshell inside it.
- `internal/greeter/` - installer, session launcher, per-user cache sync and access checks (the `greeter` group and `/var/cache/dms-greeter/users/<user>/`).
- `internal/pam/` - manages `/etc/pam.d/greetd` for fingerprint (`pam_fprintd`) and U2F (`pam_u2f`). Respects existing custom PAM config.
- `internal/shellembed/` - `go:embed` of the quickshell tree, only with the `withshell` build tag. `make build` copies `quickshell/` into `internal/shellembed/dist` first (gitignored).
- `internal/matugen/`, `internal/dank16/` - theme generation from wallpaper, mirrors what DMS does.
- `internal/privesc/` - picks sudo, doas, or run0 for commands that touch system config.
- `internal/config/`, `internal/distros/`, `internal/utils/`, `internal/qmlchecks/` - compositor config templates, distro detection, helpers, and go tests that assert invariants in the QML.

Shared Go code comes from the `dankgo` module at the version pinned in `core/go.mod`. There is no unix socket server and no daemon; the greeter talks to greetd through Quickshell's own `Quickshell.Services.Greetd`.

### 2- quickshell:

The Quickshell UI. `shell.qml` is the entry and only loads `GreeterSurface`.

- `Modules/Greetd/` - the whole visible greeter: `GreeterContent` (login form, session picker, auth flow), `GreeterUserPicker`, `GreeterUserTheme`, `GreetdSettings` (reads the synced settings), `GreetdMemory` (last user and session).
- `Services/` - headless singletons that only read system state: network, battery, bluetooth, audio, weather, compositor, niri, `GreeterUsersService`. They use Quickshell's own services (UPower, Pipewire, Networking, Bluetooth). `Log` is the only logging path; `console.*` is rejected by pre-commit.
- `Common/` - Theme, SettingsData, SessionData, I18n, Paths, StockThemes. Trimmed copies of the DMS equivalents.
- `Widgets/` - one-line re-exports of `DankCommon` widgets so QML here can `import qs.Widgets` like DMS does.
- `DankCommon/` - symlink into the `dank-qml-common` submodule. Never edit through the symlink.
- `translations/` - POEditor-synced catalogs. `make i18n-*` targets drive them.

### Other directories:

- `dank-qml-common/` - git submodule, the shared Dank widget library. Bump with `make update-common`, which also updates the nix flake input. Commit both together.
- `distro/` - packaging for debian, ubuntu, fedora, opensuse, void, plus the NixOS module in `distro/nix`. `distro/scripts/` and `scripts/` are the OBS, COPR, PPA, and void publishing scripts used by CI.
- `assets/` - sysusers and tmpfiles configs under `assets/systemd`, example compositor configs under `assets/examples`.
- `flake.nix` - nix package and NixOS module (`programs.dms-greeter`).

## Build and run

```
make build      # release binary, UI embedded (needs the submodule)
make dev        # fast go build, no embedded UI
make test       # go test ./... under core
```

`dms-greeter sync --local` from a checkout installs a dev binary as `/usr/local/bin/dms-greeter-local` and points greetd at it. Plain `dms-greeter sync` points greetd back at the packaged binary.

To iterate on QML without greetd, run quickshell headless against the checkout:

```
QT_QPA_PLATFORM=offscreen DMS_RUN_GREETER=1 qs -p quickshell
```

Pre-commit runs gofmt, go vet, go test, go mod tidy, and the no-console-in-QML check.

## General Rules:

- Keep it simple. Do not overcomplicate things.
- This runs as the `greeter` system user before anyone is logged in. Be careful with file permissions, the `greeter` group, and anything that reads from `/var/cache/dms-greeter`. Never assume a home directory or a logged-in user.
- The greeter must never write to a user's DMS config. Sync is one direction, DMS to greeter.
- Stay in step with DMS. `Common/` and `Services/` here are trimmed copies of DMS files. When fixing something that also exists in DMS, fix it the same way in both, and prefer moving shared code into `dank-qml-common`.
- Resource usage matters. The greeter sits on the login screen indefinitely. Audit any change for idle CPU cost, timers, polling, and extra processes.
- Follow each app's own conventions. QML uses Theme tokens instead of hardcoded colors, spacing, or other constants.
- Use the Dank* wrappers in `Widgets/` or `DankCommon/Widgets` instead of raw ListView/Flickable/ScrollView.
- All user-facing text goes through I18n.tr(). Prefer reusing existing catalog terms over adding new ones. Never edit the translation catalogs by hand, they are synced with POEditor.
- Use the `Log` service in QML, never `console.*`.
- The Go binary is pure Go, `CGO_ENABLED=0`. Do not add cgo dependencies.
- Anything that edits system config (greetd config, PAM, niri config under `/etc/greetd`) goes through `internal/privesc`, and must respect existing user customizations.
- Do not start editing code in response to a question. We'll tell you when to edit code.
- Do not leave paragraphs of comments on top of the code. Avoid comments as much as possible with understandable function names and code. If they are necessary even then, make them concise. Remove such comments when you come by them in the codebase. Comments should always move with code, not be left behind.
- Use guard statement patterns in any code you write.
- Do not write any useless tests, tests should cover input output validation - not useless things like "main.go contains func main()".
- If we are missing a glaring issue when we ask you to do something, do not hesitate to point it out.
- Reinvent the wheel but do not reinvent the car. If you are solving a simple problem do not introduce a library. If you are solving a complex but a common problem, there is likely a modern library for it, if so, use it.
- Never commit or push code unless explicitly asked to do so.
- Never make a PR unless explicitly asked to do so.

## Commit Messages

Commit messages start with the part of the system they touched, followed by a short lowercase explanation of the work:

greeter: let the on-screen keyboard type into the password field
sync: link per-user slots to live DMS state instead of copying

The title should be concise. Description should explain the work in more detail (only if required) while still being concise. Use simple language, do not try to sound smart.
