# Handoff: dank-greeter packaging cutover + `dms-greeter-git`

**Audience:** next agent / human continuing packaging work  
**Repo focus:** [`AvengeMedia/dank-greeter`](https://github.com/AvengeMedia/dank-greeter)  
**Related:** `danklinux`, `danklinux-docs`, `dms` (DankMaterialShell)  
**Status as of:** 2026-07-20 (evening)

---

## CRITICAL — Git / commit hard-stops

**Do not commit, amend, push, force-push, or create PRs unless the user explicitly asks in the current message.**

| Rule | Detail |
|------|--------|
| No agent commits | User rules forbid `git commit` / `git push` unless explicitly requested. Treat as hard. |
| No Co-authored-by | Never add Cursor / agent trailers. |
| No secrets in-repo | Do **not** recreate secrets notes files. Secret **names** only in chat / this handoff. |
| Review before publish | Leave packaging edits for the user to review. Summarize diffs; do not land them. |

**Incident (cleaned):** An earlier agent committed + pushed secrets notes + `Co-authored-by: Cursor`. Tip rewritten to `3c39dea`. Do not repeat.

---

## Goal

1. Greeter packaging origin is **dank-greeter**, not DMS.  
2. Packages publish into **danklinux** channels (Copr / OBS / PPA / Void R2).  
3. Stable `dms-greeter` stays live; **`dms-greeter-git`** is a separate package (Provides + Conflicts `dms-greeter`, same `/usr/bin/dms-greeter`).  
4. Prove cutover on every channel, then push + prove GitHub Actions secrets.

---

## Where we are (summary)

| Layer | Status |
|-------|--------|
| **In-tree packaging** for `dms-greeter-git` (Fedora, OBS openSUSE+Debian, Ubuntu PPA, Void) | **Done locally / uncommitted** |
| **Workflows** unified dropdowns (`dms-greeter` \| `dms-greeter-git` \| `both`) | **Done locally / uncommitted** |
| **dank-greeter GitHub Actions secrets** | **User reports all set** |
| **Docs** (danklinux-docs install tabs + dank-greeter README) | **Updated ahead of publish** (docs repo may have its own uncommitted/staged set) |
| **Copr** `dms-greeter-git` | Package exists; earlier build succeeded |
| **OBS** `dms-greeter-git` | Package **created**; first upload had Debian fail; **fixed in tree but rebuild not uploaded yet** |
| **PPA** `dms-greeter-git` | Packaging ready; **upload not started** |
| **Void R2** `dms-greeter-git` | Template ready; **build/publish not started** |
| **Commit / push of this work** | **Not done** — waiting on user |

---

## What is done (detail)

### Fedora / Copr

- Specs: `distro/fedora/dms-greeter.spec` + `dms-greeter-git.spec` (mutual Conflicts).  
- Scripts: `copr-upload.sh` (unified; `dms-greeter` \| `dms-greeter-git`; empty-tag fallback → `1.0.0+git…`).  
- Workflow: `.github/workflows/run-copr.yml` (dropdown; deleted `run-copr-git.yml` + `copr-upload-git.sh`).  
- Copr project `avengemedia/danklinux` already has both package names.  
- Prior proof build: [10748722](https://copr.fedorainfracloud.org/coprs/build/10748722).

### OBS (openSUSE + Debian)

- Specs/trees: `distro/opensuse/dms-greeter-git.spec`, `distro/debian/dms-greeter-git/`.  
- Stable openSUSE/Debian: `Conflicts: dms-greeter-git`.  
- Script: `obs-upload.sh` supports `dms-greeter` \| `dms-greeter-git`; creates OBS package if missing; packs checkout + submodule + `go mod vendor`; Python spec rewriter (sed broke on `+` in git versions).  
- Workflow: `run-obs.yml` dropdown + submodules + Go for vendoring.  
- **Live OBS:** `home:AvengeMedia:danklinux/dms-greeter-git` **exists**.  
- **First local upload** (`1.0.0+git9.d73d3c04`): openSUSE arches **succeeded**; **Debian_13 failed** because `dh_auto_test` ran `make test` without bundled Go on `PATH`.  
- **Fix in tree (not re-uploaded):** `override_dh_auto_test` on Debian (+ Ubuntu) `debian/rules` for greeter and greeter-git.  
- Rebuild CLI: bare integer or `--rebuild=N` — e.g.  
  `./distro/scripts/obs-upload.sh dms-greeter-git 2`

### Ubuntu PPA

- Tree: `distro/ubuntu/dms-greeter-git/` (Provides/Conflicts/Replaces; packs `dms-greeter-git-source/` with vendor + DankCommon).  
- Stable Ubuntu: `Conflicts: dms-greeter-git` + `override_dh_auto_test`.  
- Script: `ppa-upload.sh [dms-greeter|dms-greeter-git] [series] [ppa_num]`.  
- Workflow: `run-ppa.yml` package dropdown including `both`.  
- **GPG:** local key imported (`F16508F357F99EE9`); signing works.  
- **Upload abort (fixed):** `yes | debuild` under `pipefail` exited 141 after sign — now `debuild … </dev/null`.  
- **Launchpad:** amd64 **succeeded**; arm64 **failed** (~11m, no build log — mid `go build`). Aligned git PPA with **dankcalendar-git** blueprint: bundle `.go-toolchain` in `ppa-upload.sh`, `PATH` in `debian/rules`, `Architecture: any`, drop bogus `include-binaries`. Re-upload with bumped ppa number to prove arm64.

### Void XBPS / R2

- Template: `distro/void/srcpkgs/dms-greeter-git/` (`conflicts`/`provides`; CI stages tarball).  
- Stable Void: `conflicts="dms-greeter-git"`.  
- Workflow: `run-xbps.yml` supports greeter / git / both; `R2_PREFIX=dms` unchanged.  
- **No Void git build/publish yet.**

### Docs / README

- `danklinux-docs` `docs/dankgreeter/installation.mdx`: stable/git tabs for Fedora, Debian, Ubuntu, openSUSE, Void (written ahead of channel publish — user will push when verified).  
- `danklinux/index.mdx` (staged earlier): lists `dms-greeter` + `dms-greeter-git`.  
- dank-greeter `README.md`: mentions git install on OBS/PPA/Void/Copr.

### Secrets (names only — values in GitHub UI)

User has populated dank-greeter Actions secrets. Names:

`COPR_LOGIN`, `COPR_TOKEN`, `OBS_USERNAME`, `OBS_PASSWORD`, `GPG_PRIVATE_KEY`, `LAUNCHPAD_SSH_PRIVATE_KEY`, `LAUNCHPAD_SSH_LOGIN`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `CLOUDFLARE_ACCOUNT_ID`, `XBPS_PRIVATE_KEY`, `APP_ID`, `APP_PRIVATE_KEY`

- `COPR_LOGIN` = opaque API `login=` value only (not username; workflow hardcodes `username = avengemedia`).  
- `GITHUB_TOKEN` = builtin; do not create as a repo secret.  
- Local key backup zip: `~/Downloads/API_SSH_Keys.zip` (encrypted danklinux migration archive) + `~/Downloads/Projects/GPG-Keys.zip`.

### Local smoke already run

- `bash -n` on all `distro/scripts/*.sh`  
- OBS-style pack + vendor (~11M)  
- Fedora git SRPM built locally (not necessarily re-uploaded)  
- OBS package create + first upload (Debian fail as above)

---

## Architecture (target)

```text
dank-greeter (source + packaging + CI)
    │
    ├── Copr  → avengemedia/danklinux
    │             ├── dms-greeter
    │             └── dms-greeter-git      ← live earlier; keep healthy
    ├── OBS   → home:AvengeMedia:danklinux
    │             ├── dms-greeter          ← stable live
    │             └── dms-greeter-git      ← created; needs Debian-fix rebuild upload
    ├── PPA   → ppa:avengemedia/danklinux
    │             ├── dms-greeter          ← stable
    │             └── dms-greeter-git      ← packaging ready; not uploaded
    └── Void  → void.danklinux.com/dms/current
                  ├── dms-greeter
                  └── dms-greeter-git      ← packaging ready; not published
```

Binary for all: `/usr/bin/dms-greeter`.

---

## Next agent goal — publish + verify (do not commit unless asked)

Packaging code is largely ready. Remaining work is **upload/build proof**, then user commit/push, then **Actions secret proof**.

### Suggested order

1. **OBS rebuild with Debian fix** (local, uses `~/.config/osc`):  
   `./distro/scripts/obs-upload.sh dms-greeter-git 2`  
   Then `./distro/scripts/obs-status.sh dms-greeter-git` until Debian_13 + openSUSE green.

2. **PPA git** (local first if GPG + Launchpad ready):  
   `./distro/scripts/ppa-upload.sh dms-greeter-git resolute`  
   Watch Launchpad builds.

3. **Void git** — after push or via Actions `run-xbps.yml` with `dms-greeter-git` (needs R2/XBPS secrets in CI). Local xbps-src optional.

4. **User review + commit + push** all dank-greeter packaging/workflow changes (and docs when ready).

5. **Prove GitHub secrets** via `workflow_dispatch`:  
   - `run-copr.yml` → `dms-greeter-git`  
   - `run-obs.yml` → `dms-greeter-git`  
   - `run-ppa.yml` → `dms-greeter-git`  
   - `run-xbps.yml` → `dms-greeter-git`  
   Local scripts prove local creds/builds; **only Actions prove repo secrets**.

6. **Docs:** already drafted for git installs; only push/publish docs once channels actually ship (or keep as-is per user preference to ship together).

### Design constraints (unchanged)

- Package name `dms-greeter-git`; mutual Conflicts; Prefer Provides `dms-greeter`.  
- Pack `dank-qml-common`; restore `quickshell/DankCommon` symlink.  
- OBS Debian/openSUSE: offline → vendor + bundled Go.  
- PPA: distro `golang-go` + vendored tree in native source.  
- Void: `R2_PREFIX=dms`; coordinate with dms Void publishes.  
- Do not force-republish stable unless asked.

### Gotchas already hit

| Issue | Fix |
|-------|-----|
| `sed` dies on Version `1.0.0+git…` in `obs-upload.sh` | Python rewriter in `update_opensuse_git_spec` |
| `GO_VER=$(stage_go_toolchains)` polluted by stdout logs | Status → stderr; validate version token |
| OBS Debian `go: not found` in `dh_auto_test` | `override_dh_auto_test` in debian/ubuntu rules |
| `ppa-upload.sh dms-greeter-git` was unknown | Script now accepts package name |
| (was) bare `2` ignored as message | Fixed: bare integer sets rebuild; `--rebuild=N` still works |
| Empty `git describe` (no tags) | Fallback base `1.0.0` |
| PPA `yes \| debuild` → exit 141 after sign | Drop `yes`; `debuild … </dev/null` |

### Reference files

- Fedora: `distro/fedora/dms-greeter-git.spec`, `distro/scripts/copr-upload.sh`  
- OBS: `distro/opensuse/dms-greeter-git.spec`, `distro/debian/dms-greeter-git/`, `distro/scripts/obs-upload.sh`  
- PPA: `distro/ubuntu/dms-greeter-git/`, `distro/scripts/ppa-upload.sh`  
- Void: `distro/void/srcpkgs/dms-greeter-git/`, `.github/workflows/run-xbps.yml`  
- Workflows: `.github/workflows/run-{copr,obs,ppa,xbps}.yml`

---

## Verification checklist

- [ ] User reviewed/committed packaging + workflow changes  
- [ ] OBS `dms-greeter-git` rebuild uploaded; Debian_13 + openSUSE all green  
- [ ] PPA `dms-greeter-git` uploaded and Launchpad build succeeded  
- [ ] Void `dms-greeter-git` built and published to `void.danklinux.com/dms/current`  
- [ ] Actions dispatch proves Copr/OBS/PPA/Void secrets on dank-greeter  
- [ ] `dnf` / `apt` / `zypper` / `xbps-install` git install paths work  
- [ ] No secrets markdown or Co-authored-by in agent-touched commits  
- [ ] Docs pushed only when channels match documented install steps (or intentionally ahead)

---

## Out of scope (still)

- AUR `greetd-dms-greeter-git` / `-bin` (external).  
- Republishing stable greeter until next tag (unless user asks).  
- Changing Void `R2_PREFIX` away from `dms`.

---

## Handoff one-liner

**In-tree `dms-greeter-git` packaging for Copr/OBS/PPA/Void is ready locally (uncommitted); OBS package exists but needs rebuild `2` after the Debian `dh_auto_test` fix; PPA and Void git uploads not started; secrets are in GitHub — prove them with Actions after user push; do not commit unless asked.**
