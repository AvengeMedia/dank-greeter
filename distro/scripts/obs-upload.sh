#!/bin/bash
# OBS upload for dms-greeter / dms-greeter-git (home:AvengeMedia:danklinux).
#
# Stable (dms-greeter): release tarball + vendored Go from GitHub releases.
# Git (dms-greeter-git): packs the current checkout (submodule + go mod vendor)
# into dms-greeter-git-source.tar.gz; versions as BASE+gitCOUNT.HASH.
#
# Usage:
#   ./distro/scripts/obs-upload.sh [debian|opensuse] [dms-greeter|dms-greeter-git] [--version=X.Y.Z] [--rebuild=N|N] [message]
#
# Examples:
#   ./distro/scripts/obs-upload.sh "Update to v1.0.0"
#   ./distro/scripts/obs-upload.sh opensuse --version=1.0.0
#   ./distro/scripts/obs-upload.sh dms-greeter-git
#   ./distro/scripts/obs-upload.sh dms-greeter-git 2
#   ./distro/scripts/obs-upload.sh debian dms-greeter-git --rebuild=2

set -euo pipefail

REPO="AvengeMedia/dank-greeter"
PACKAGE="dms-greeter"
OBS_PROJECT="home:AvengeMedia:danklinux"
OBS_BASE="${OBS_BASE:-$HOME/.cache/osc-checkouts}"
DEB_EPOCH=1
MAINTAINER="Avenge Media <AvengeMedia.US@gmail.com>"
GO_TOOLCHAIN_CACHE="${GO_TOOLCHAIN_CACHE:-$HOME/.cache/dms-greeter-obs-go-toolchain}"

UPLOAD_DEBIAN=true
UPLOAD_OPENSUSE=true
VERSION=""
MESSAGE=""
REBUILD_RELEASE="${REBUILD_RELEASE:-}"

for arg in "$@"; do
    case "$arg" in
    debian)
        UPLOAD_DEBIAN=true
        UPLOAD_OPENSUSE=false
        ;;
    opensuse)
        UPLOAD_DEBIAN=false
        UPLOAD_OPENSUSE=true
        ;;
    dms-greeter|dms-greeter-git)
        PACKAGE="$arg"
        ;;
    --version=*)
        VERSION="${arg#*=}"
        VERSION="${VERSION#v}"
        ;;
    --rebuild=*)
        REBUILD_RELEASE="${arg#*=}"
        ;;
    ''|*[!0-9]*)
        # Non-numeric leftover → commit message (empty skipped via '')
        if [[ -n "$arg" ]]; then
            MESSAGE="$arg"
        fi
        ;;
    *)
        # Bare integer shorthand: ... dms-greeter-git 2
        REBUILD_RELEASE="$arg"
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "distro/debian/$PACKAGE" ]]; then
    echo "Error: Package tree missing: distro/debian/$PACKAGE"
    echo "Run this script from the dank-greeter repository"
    exit 1
fi

IS_GIT=false
if [[ "$PACKAGE" == *-git ]]; then
    IS_GIT=true
fi

# Retry wrapper for osc commands (mitigates transient api.opensuse.org resets)
osc_retry() {
    local max=3 attempt=1
    while true; do
        if osc "$@"; then return 0; fi
        ((attempt >= max)) && return 1
        echo "Retrying in $((5*attempt))s (attempt $attempt/$max)..."
        sleep $((5*attempt))
        ((attempt++))
    done
}

ensure_obs_package() {
    if osc meta pkg "$OBS_PROJECT" "$PACKAGE" &>/dev/null; then
        return 0
    fi
    echo "==> Creating OBS package $OBS_PROJECT/$PACKAGE"
    osc meta pkg "$OBS_PROJECT" "$PACKAGE" -F - <<EOF
<package name="$PACKAGE" project="$OBS_PROJECT">
  <title>$PACKAGE</title>
  <description>DMS Greeter packaging from dank-greeter</description>
</package>
EOF
}

go_toolchain_version() {
    grep -m1 '^go ' "$REPO_ROOT/core/go.mod" 2>/dev/null | awk '{print $2}'
}

stage_go_toolchains() {
    local dest="$1"
    local ver arch url cached
    ver="$(go_toolchain_version)"
    if [[ -z "$ver" ]]; then
        echo "Error: Could not read Go version from core/go.mod"
        exit 1
    fi
    mkdir -p "$GO_TOOLCHAIN_CACHE/$ver"
    for arch in amd64 arm64; do
        url="https://go.dev/dl/go${ver}.linux-${arch}.tar.gz"
        cached="$GO_TOOLCHAIN_CACHE/$ver/go${ver}.linux-${arch}.tar.gz"
        if [[ ! -f "$cached" ]]; then
            # stdout must stay clean: callers capture this function's version via $()
            echo "    Downloading Go ${ver} (${arch})..." >&2
            if wget -q -O "${cached}.tmp" "$url" 2>/dev/null || curl -L -f -s -o "${cached}.tmp" "$url"; then
                mv "${cached}.tmp" "$cached"
            else
                rm -f "${cached}.tmp"
                echo "Error: Failed to download $url" >&2
                exit 1
            fi
        fi
        cp -f "$cached" "$dest/go${ver}.linux-${arch}.tar.gz"
    done
    echo "    Go toolchain ${ver} staged" >&2
    # Single clean token only — never log on stdout
    printf '%s' "$ver"
}

# Pack current checkout for git OBS builds (submodule + vendor + DankCommon link)
pack_git_source_tree() {
    local dest_dir="$1"
    local tmp pack_root

    if [[ ! -e "$REPO_ROOT/dank-qml-common/DankCommon/Widgets/DankIcon.qml" ]]; then
        echo "Error: dank-qml-common submodule missing. Run: git submodule update --init"
        exit 1
    fi

    tmp="$(mktemp -d)"
    pack_root="$tmp/dms-greeter-git-source"
    mkdir -p "$pack_root"

    # Tracked files via git archive, then overlay submodule (archive skips submodule content)
    git archive --format=tar HEAD | tar -x -C "$pack_root"
    rm -rf "$pack_root/dank-qml-common"
    mkdir -p "$pack_root/dank-qml-common"
    tar -C "$REPO_ROOT/dank-qml-common" --exclude='.git' -cf - . \
        | tar -C "$pack_root/dank-qml-common" -xf -
    rm -rf "$pack_root/quickshell/DankCommon"
    ln -sfn ../dank-qml-common/DankCommon "$pack_root/quickshell/DankCommon"
    test -e "$pack_root/quickshell/DankCommon/Widgets/DankIcon.qml" \
        || { echo "Error: DankCommon missing after pack"; exit 1; }

    # Vendor Go deps for offline OBS (release tarballs already vendor; git may not)
    if [[ ! -d "$pack_root/core/vendor" ]]; then
        echo "  - Vendoring Go dependencies for offline OBS build..."
        if ! command -v go &>/dev/null; then
            echo "Error: Go not found; needed to vendor dependencies for git OBS uploads"
            exit 1
        fi
        (cd "$pack_root/core" && go mod vendor)
        test -d "$pack_root/core/vendor" || { echo "Error: go mod vendor failed"; exit 1; }
        echo "    ✓ Vendored ($(du -sh "$pack_root/core/vendor" | cut -f1))"
    fi

    mkdir -p "$dest_dir"
    rm -rf "$dest_dir/dms-greeter-git-source"
    mv "$pack_root" "$dest_dir/dms-greeter-git-source"
    rm -rf "$tmp"
}

update_opensuse_git_spec() {
    local spec_path="$1"
    local go_ver="$2"
    local changelog_version="$3"
    local commit_count="$4"
    local commit_hash="$5"
    local release_num="${REBUILD_RELEASE:-1}"
    local date_str

    # Avoid sed with versions containing '+' (e.g. 1.0.0+git9.abcd) — it breaks
    # delimiter/escaping on some sed builds. Rewrite fields in Python instead.
    date_str=$(date '+%a %b %d %Y')
    python3 - "$spec_path" "$go_ver" "$changelog_version" "$release_num" \
        "$date_str" "$commit_count" "$commit_hash" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
go_ver, version, release, date_str, commit_count, commit_hash = sys.argv[2:8]
text = path.read_text()
lines = text.splitlines(keepends=True)
out = []
for line in lines:
    if line.startswith("%global go_toolchain_version"):
        out.append(f"%global go_toolchain_version {go_ver}\n")
    elif line.startswith("Version:"):
        out.append(f"Version:        {version}\n")
    elif line.startswith("Release:"):
        out.append(f"Release:        {release}%{{?dist}}\n")
    elif line.startswith("%changelog"):
        break
    else:
        out.append(line if line.endswith("\n") else line + "\n")
out.append("%changelog\n")
out.append(
    f"* {date_str} AvengeMedia <contact@avengemedia.com> - 1:{version}-{release}\n"
)
out.append(f"- Git snapshot (commit {commit_count}: {commit_hash})\n")
path.write_text("".join(out))
PY
}

# ---------------------------------------------------------------------------
# Version resolution
# ---------------------------------------------------------------------------
COMMIT_HASH=""
COMMIT_COUNT=""
CHANGELOG_VERSION=""
DEB_FULL_VERSION=""
RELEASE="${REBUILD_RELEASE:-1}"

if [[ "$IS_GIT" == true ]]; then
    COMMIT_HASH=$(git rev-parse --short=8 HEAD)
    COMMIT_COUNT=$(git rev-list --count HEAD)
    BASE_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
    if [[ -z "$BASE_VERSION" ]]; then
        BASE_VERSION="1.0.0"
    fi
    CHANGELOG_VERSION="${BASE_VERSION}+git${COMMIT_COUNT}.${COMMIT_HASH}"
    if [[ -n "$REBUILD_RELEASE" ]]; then
        CHANGELOG_VERSION="${CHANGELOG_VERSION}db${REBUILD_RELEASE}"
    fi
    DEB_FULL_VERSION="${DEB_EPOCH}:${CHANGELOG_VERSION}"
    VERSION="$CHANGELOG_VERSION"
    if [[ -z "$MESSAGE" ]]; then
        MESSAGE="Git snapshot ${CHANGELOG_VERSION}"
    fi
else
    if [[ -z "$VERSION" ]]; then
        VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": "v\{0,1\}\([^"]*\)".*/\1/' || echo "")
        if [[ -z "$VERSION" ]]; then
            echo "Error: Could not determine latest release version"
            exit 1
        fi
        echo "==> Using latest release: $VERSION"
    fi
    CHANGELOG_VERSION="${VERSION}db${RELEASE}"
    DEB_FULL_VERSION="${DEB_EPOCH}:${CHANGELOG_VERSION}"
    if [[ -z "$MESSAGE" ]]; then
        MESSAGE="Update to v${VERSION}"
    fi
fi

echo "==> Target: $OBS_PROJECT / $PACKAGE ($VERSION, release $RELEASE)"

# Skip when this version/release is already on OBS (unless forced)
if [[ -z "${FORCE_UPLOAD:-}" ]]; then
    if [[ "$IS_GIT" == true ]]; then
        OBS_SPEC=$(osc api "/source/$OBS_PROJECT/$PACKAGE/${PACKAGE}.spec" 2>/dev/null || echo "")
        if [[ "$OBS_SPEC" == *"Version:"* ]]; then
            OBS_VERSION=$(echo "$OBS_SPEC" | grep "^Version:" | awk '{print $2}' | xargs)
            # Compare without dbN rebuild suffix
            WANT_BASE=$(echo "$CHANGELOG_VERSION" | sed 's/db[0-9]*$//')
            HAVE_BASE=$(echo "$OBS_VERSION" | sed 's/db[0-9]*$//')
            if [[ "$WANT_BASE" == "$HAVE_BASE" ]] && [[ -z "$REBUILD_RELEASE" ]]; then
                echo "==> Git commit already on OBS as $OBS_VERSION"
                if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                    echo "✓ Exiting gracefully (no changes needed)"
                    exit 0
                fi
                echo "    To rebuild: ./distro/scripts/obs-upload.sh $PACKAGE 2"
                exit 1
            fi
            if [[ -n "$REBUILD_RELEASE" ]] && [[ "$OBS_VERSION" == "$CHANGELOG_VERSION" ]]; then
                echo "==> Version $CHANGELOG_VERSION already exists in OBS"
                echo "✓ Exiting gracefully (no changes needed)"
                exit 0
            fi
        fi
    else
        OBS_SPEC=$(osc api "/source/$OBS_PROJECT/$PACKAGE/${PACKAGE}.spec" 2>/dev/null || echo "")
        if [[ "$OBS_SPEC" == *"Version:"* ]]; then
            OBS_VERSION=$(echo "$OBS_SPEC" | grep "^Version:" | awk '{print $2}' | xargs)
            OBS_RELEASE=$(echo "$OBS_SPEC" | grep "^Release:" | sed 's/^Release:[[:space:]]*//; s/%{?dist}//' | xargs)
            if [[ "$OBS_VERSION" == "$VERSION" ]]; then
                if [[ -z "$REBUILD_RELEASE" ]] || [[ "$OBS_RELEASE" == "$RELEASE" ]]; then
                    echo "==> Version $VERSION (release $OBS_RELEASE) already exists in OBS"
                    if [[ -z "$REBUILD_RELEASE" ]]; then
                        echo "    To rebuild the same version: ./distro/scripts/obs-upload.sh $PACKAGE $((OBS_RELEASE + 1))"
                    fi
                    echo "✓ Exiting gracefully (no changes needed)"
                    exit 0
                fi
            fi
        fi
    fi
fi

ensure_obs_package

mkdir -p "$OBS_BASE"
if [[ ! -d "$OBS_BASE/$OBS_PROJECT/$PACKAGE" ]]; then
    echo "==> Checking out $OBS_PROJECT/$PACKAGE..."
    (cd "$OBS_BASE" && osc_retry co "$OBS_PROJECT/$PACKAGE")
fi
WORK_DIR="$OBS_BASE/$OBS_PROJECT/$PACKAGE"

echo "==> Preparing $PACKAGE for OBS upload"
find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.spec" -o -name "*.dsc" -o -name "_service" \) -delete 2>/dev/null || true

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

GO_VER=""
SOURCE_TARBALL=""
COMBINED_TARBALL=""

if [[ "$IS_GIT" == true ]]; then
    echo "==> Packing git snapshot from local checkout"
    pack_git_source_tree "$TEMP_DIR"
    SOURCE_DIR="$TEMP_DIR/dms-greeter-git-source"
    SOURCE_TARBALL="dms-greeter-git-source.tar.gz"

    GO_VER="$(stage_go_toolchains "$WORK_DIR" | tr -d '[:space:]')"
    if [[ ! "$GO_VER" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
        echo "Error: Invalid Go toolchain version captured: ${GO_VER@Q}" >&2
        exit 1
    fi

    if [[ "$UPLOAD_OPENSUSE" == true ]]; then
        echo "  - Preparing OpenSUSE git spec + source tarball"
        cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"
        # Strip dbN for RPM Version: (Debian may keep it)
        RPM_VERSION="${CHANGELOG_VERSION%%db*}"
        update_opensuse_git_spec "$WORK_DIR/$PACKAGE.spec" "$GO_VER" "$RPM_VERSION" "$COMMIT_COUNT" "$COMMIT_HASH"
        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 \
            -czf "$WORK_DIR/$SOURCE_TARBALL" -C "$TEMP_DIR" "dms-greeter-git-source"
    fi

    if [[ "$UPLOAD_DEBIAN" == true ]]; then
        echo "  - Preparing Debian native source (combined tarball + .dsc)"
        # Fresh tree for debian (may share with opensuse pack above)
        if [[ ! -d "$SOURCE_DIR" ]]; then
            pack_git_source_tree "$TEMP_DIR"
            SOURCE_DIR="$TEMP_DIR/dms-greeter-git-source"
        fi
        cp -r "distro/debian/$PACKAGE/debian" "$SOURCE_DIR/"
        cat >"$SOURCE_DIR/debian/changelog" <<EOF
$PACKAGE ($DEB_FULL_VERSION) unstable; urgency=medium

  * Git snapshot (commit ${COMMIT_COUNT}: ${COMMIT_HASH})

 -- $MAINTAINER  $(date -R)
EOF
        cp "$WORK_DIR"/go${GO_VER}.linux-*.tar.gz "$SOURCE_DIR/"

        COMBINED_TARBALL="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 \
            -czf "$WORK_DIR/$COMBINED_TARBALL" -C "$TEMP_DIR" "dms-greeter-git-source"

        TARBALL_MD5=$(md5sum "$WORK_DIR/$COMBINED_TARBALL" | cut -d' ' -f1)
        TARBALL_SIZE=$(stat -c%s "$WORK_DIR/$COMBINED_TARBALL")

        BUILD_DEPS=$(awk '
            /^Build-Depends:/ {
                in_build_deps=1;
                sub(/^Build-Depends:[[:space:]]*/, "");
                printf "%s", $0;
                next;
            }
            in_build_deps && /^[[:space:]]/ {
                sub(/^[[:space:]]+/, " ");
                printf "%s", $0;
                next;
            }
            in_build_deps { exit; }
        ' "distro/debian/$PACKAGE/debian/control" | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -n "$BUILD_DEPS" ]] || BUILD_DEPS="debhelper-compat (= 13)"

        cat >"$WORK_DIR/$PACKAGE.dsc" <<EOF
Format: 3.0 (native)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: amd64 arm64
Version: $DEB_FULL_VERSION
Maintainer: $MAINTAINER
Build-Depends: $BUILD_DEPS
Files:
 $TARBALL_MD5 $TARBALL_SIZE $COMBINED_TARBALL
EOF
    fi

    if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
        cp "distro/debian/$PACKAGE/_service" "$WORK_DIR/"
    fi
else
    # Stable: download release tarball
    SOURCE_TARBALL="dank-greeter-${VERSION}.tar.gz"
    SOURCE_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${SOURCE_TARBALL}"
    echo "==> Downloading $SOURCE_URL"
    if ! { wget -q -O "$WORK_DIR/$SOURCE_TARBALL" "$SOURCE_URL" 2>/dev/null || curl -L -f -s -o "$WORK_DIR/$SOURCE_TARBALL" "$SOURCE_URL"; }; then
        echo "Error: Failed to download $SOURCE_URL"
        exit 1
    fi

    GO_VER=$(tar -xzOf "$WORK_DIR/$SOURCE_TARBALL" "dank-greeter-${VERSION}/core/go.mod" | grep -m1 '^go ' | awk '{print $2}')
    if [[ -z "$GO_VER" ]]; then
        echo "Error: Could not read Go version from the release tarball's core/go.mod"
        exit 1
    fi
    mkdir -p "$GO_TOOLCHAIN_CACHE/$GO_VER"
    for arch in amd64 arm64; do
        cached="$GO_TOOLCHAIN_CACHE/$GO_VER/go${GO_VER}.linux-${arch}.tar.gz"
        if [[ ! -f "$cached" ]]; then
            echo "    Downloading Go ${GO_VER} (${arch})..."
            url="https://go.dev/dl/go${GO_VER}.linux-${arch}.tar.gz"
            if wget -q -O "${cached}.tmp" "$url" 2>/dev/null || curl -L -f -s -o "${cached}.tmp" "$url"; then
                mv "${cached}.tmp" "$cached"
            else
                rm -f "${cached}.tmp"
                echo "Error: Failed to download $url"
                exit 1
            fi
        fi
        cp -f "$cached" "$WORK_DIR/go${GO_VER}.linux-${arch}.tar.gz"
    done
    echo "    Go toolchain ${GO_VER} staged"

    if [[ "$UPLOAD_OPENSUSE" == true ]]; then
        echo "  - Preparing OpenSUSE spec"
        CHANGELOG_DATE=$(date '+%a %b %d %Y')
        cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"
        sed -i "s/^%global go_toolchain_version .*/%global go_toolchain_version ${GO_VER}/" "$WORK_DIR/$PACKAGE.spec"
        sed -i "s/VERSION_PLACEHOLDER/${VERSION}/g" "$WORK_DIR/$PACKAGE.spec"
        sed -i "s/RELEASE_PLACEHOLDER/${RELEASE}/g" "$WORK_DIR/$PACKAGE.spec"
        sed -i "s/CHANGELOG_DATE_PLACEHOLDER/${CHANGELOG_DATE}/g" "$WORK_DIR/$PACKAGE.spec"
    fi

    if [[ "$UPLOAD_DEBIAN" == true ]]; then
        echo "  - Preparing Debian native source (combined tarball + .dsc)"
        tar -xzf "$WORK_DIR/$SOURCE_TARBALL" -C "$TEMP_DIR"
        SOURCE_DIR="$TEMP_DIR/dank-greeter-${VERSION}"
        if [[ ! -d "$SOURCE_DIR/core/vendor" ]]; then
            echo "Error: Release tarball is missing core/vendor (offline Debian build needs it)"
            exit 1
        fi

        cp -r "distro/debian/$PACKAGE/debian" "$SOURCE_DIR/"
        cat >"$SOURCE_DIR/debian/changelog" <<EOF
$PACKAGE ($DEB_FULL_VERSION) unstable; urgency=medium

  * Update to v${VERSION} stable release

 -- $MAINTAINER  $(date -R)
EOF

        cp "$WORK_DIR"/go${GO_VER}.linux-*.tar.gz "$SOURCE_DIR/"

        COMBINED_TARBALL="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 \
            -czf "$WORK_DIR/$COMBINED_TARBALL" -C "$TEMP_DIR" "dank-greeter-${VERSION}"

        TARBALL_MD5=$(md5sum "$WORK_DIR/$COMBINED_TARBALL" | cut -d' ' -f1)
        TARBALL_SIZE=$(stat -c%s "$WORK_DIR/$COMBINED_TARBALL")

        BUILD_DEPS=$(awk '
            /^Build-Depends:/ {
                in_build_deps=1;
                sub(/^Build-Depends:[[:space:]]*/, "");
                printf "%s", $0;
                next;
            }
            in_build_deps && /^[[:space:]]/ {
                sub(/^[[:space:]]+/, " ");
                printf "%s", $0;
                next;
            }
            in_build_deps { exit; }
        ' "distro/debian/$PACKAGE/debian/control" | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -n "$BUILD_DEPS" ]] || BUILD_DEPS="debhelper-compat (= 13)"

        cat >"$WORK_DIR/$PACKAGE.dsc" <<EOF
Format: 3.0 (native)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: amd64 arm64
Version: $DEB_FULL_VERSION
Maintainer: $MAINTAINER
Build-Depends: $BUILD_DEPS
Files:
 $TARBALL_MD5 $TARBALL_SIZE $COMBINED_TARBALL
EOF
    fi
fi

if [[ "$UPLOAD_DEBIAN" == false ]]; then
    rm -f "$WORK_DIR"/*.dsc
fi
if [[ "$UPLOAD_OPENSUSE" == false ]]; then
    rm -f "$WORK_DIR"/*.spec
fi

cd "$WORK_DIR"

echo "==> Cleaning old tarballs from OBS server"
OBS_FILES=$(osc api "/source/$OBS_PROJECT/$PACKAGE" 2>/dev/null || echo "")
if [[ -n "$OBS_FILES" ]]; then
    KEEP_COMBINED="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
    for old_file in $(echo "$OBS_FILES" | grep -oP '(?<=name=")[^"]*\.tar\.gz(?=")' || true); do
        case "$old_file" in
        "$SOURCE_TARBALL"|"$KEEP_COMBINED"|go[0-9]*.linux-*.tar.gz)
            echo "  - Keeping: $old_file"
            ;;
        *)
            echo "  - Deleting from server: $old_file"
            osc api -X DELETE "/source/$OBS_PROJECT/$PACKAGE/$old_file" 2>/dev/null || true
            ;;
        esac
    done
fi

echo "==> Updating working copy"
osc_retry up

if osc status | grep -q '^C'; then
    echo "==> Resolving conflicts"
    osc status | grep '^C' | awk '{print $2}' | xargs -r osc resolved
fi

osc addremove

echo "==> Files to upload:"
ls -lh ./*.tar.gz ./*.spec ./*.dsc 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || true

if ! osc status 2>/dev/null | grep -qE '^[MAD?]'; then
    echo "==> No changes to commit (package already up to date)"
else
    echo "==> Committing to OBS"
    osc_retry commit --skip-local-service-run -m "$MESSAGE"
fi

osc results 2>&1 | head -10 || true
echo ""
echo "✅ Upload complete!"
echo "Check build status with: ./distro/scripts/obs-status.sh"
echo "OBS: https://build.opensuse.org/package/show/${OBS_PROJECT}/${PACKAGE}"
