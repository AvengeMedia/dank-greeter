#!/bin/bash
# OBS upload for the dms-greeter package (home:AvengeMedia:danklinux).
# Prepares both the Debian (native .dsc + combined tarball) and OpenSUSE
# (spec + release tarball) sources from a dank-greeter GitHub release.
# Builds are offline on OBS: the release tarball carries vendored Go deps
# and the Go toolchain is bundled alongside the sources.
#
# Usage: ./distro/scripts/obs-upload.sh [debian|opensuse] [--version=X.Y.Z] [--rebuild=N] [message]
#
# Examples:
#   ./distro/scripts/obs-upload.sh "Update to v1.0.0"
#   ./distro/scripts/obs-upload.sh opensuse --version=1.0.0
#   ./distro/scripts/obs-upload.sh --rebuild=2   # Rebuild the same version (db2 / Release 2)

set -e

REPO="AvengeMedia/dank-greeter"
PACKAGE="dms-greeter"
OBS_PROJECT="home:AvengeMedia:danklinux"
OBS_BASE="$HOME/.cache/osc-checkouts"
DEB_EPOCH=1
MAINTAINER="Avenge Media <AvengeMedia.US@gmail.com>"

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
    --version=*)
        VERSION="${arg#*=}"
        VERSION="${VERSION#v}"
        ;;
    --rebuild=*)
        REBUILD_RELEASE="${arg#*=}"
        ;;
    *)
        MESSAGE="$arg"
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "distro/debian/$PACKAGE" ]]; then
    echo "Error: Run this script from the dank-greeter repository"
    exit 1
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

if [[ -z "$VERSION" ]]; then
    VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": "v\{0,1\}\([^"]*\)".*/\1/' || echo "")
    if [[ -z "$VERSION" ]]; then
        echo "Error: Could not determine latest release version"
        exit 1
    fi
    echo "==> Using latest release: $VERSION"
fi

RELEASE="${REBUILD_RELEASE:-1}"
CHANGELOG_VERSION="${VERSION}db${RELEASE}"
DEB_FULL_VERSION="${DEB_EPOCH}:${CHANGELOG_VERSION}"

if [[ -z "$MESSAGE" ]]; then
    MESSAGE="Update to v${VERSION}"
fi

echo "==> Target: $OBS_PROJECT / $PACKAGE ($VERSION, release $RELEASE)"

# Skip when this version/release is already on OBS (unless forced)
OBS_SPEC=$(osc api "/source/$OBS_PROJECT/$PACKAGE/${PACKAGE}.spec" 2>/dev/null || echo "")
if [[ "$OBS_SPEC" == *"Version:"* ]] && [[ -z "${FORCE_UPLOAD:-}" ]]; then
    OBS_VERSION=$(echo "$OBS_SPEC" | grep "^Version:" | awk '{print $2}' | xargs)
    OBS_RELEASE=$(echo "$OBS_SPEC" | grep "^Release:" | sed 's/^Release:[[:space:]]*//; s/%{?dist}//' | xargs)
    if [[ "$OBS_VERSION" == "$VERSION" ]]; then
        if [[ -z "$REBUILD_RELEASE" ]] || [[ "$OBS_RELEASE" == "$RELEASE" ]]; then
            echo "==> Version $VERSION (release $OBS_RELEASE) already exists in OBS"
            if [[ -z "$REBUILD_RELEASE" ]]; then
                echo "    To rebuild the same version: ./distro/scripts/obs-upload.sh --rebuild=$((OBS_RELEASE + 1))"
            fi
            echo "✓ Exiting gracefully (no changes needed)"
            exit 0
        fi
    fi
fi

mkdir -p "$OBS_BASE"
if [[ ! -d "$OBS_BASE/$OBS_PROJECT/$PACKAGE" ]]; then
    echo "==> Checking out $OBS_PROJECT/$PACKAGE..."
    (cd "$OBS_BASE" && osc_retry co "$OBS_PROJECT/$PACKAGE")
fi
WORK_DIR="$OBS_BASE/$OBS_PROJECT/$PACKAGE"

echo "==> Preparing $PACKAGE for OBS upload"
find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.spec" -o -name "*.dsc" -o -name "_service" \) -delete 2>/dev/null || true

SOURCE_TARBALL="dank-greeter-${VERSION}.tar.gz"
SOURCE_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${SOURCE_TARBALL}"
echo "==> Downloading $SOURCE_URL"
if ! { wget -q -O "$WORK_DIR/$SOURCE_TARBALL" "$SOURCE_URL" 2>/dev/null || curl -L -f -s -o "$WORK_DIR/$SOURCE_TARBALL" "$SOURCE_URL"; }; then
    echo "Error: Failed to download $SOURCE_URL"
    exit 1
fi

# Bundled Go toolchain for offline OBS builds; version pinned by core/go.mod
GO_TOOLCHAIN_CACHE="${GO_TOOLCHAIN_CACHE:-$HOME/.cache/dms-greeter-obs-go-toolchain}"
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
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    tar -xzf "$WORK_DIR/$SOURCE_TARBALL" -C "$TEMP_DIR"
    SOURCE_DIR="$TEMP_DIR/dank-greeter-${VERSION}"
    if [[ ! -d "$SOURCE_DIR/core/vendor" ]]; then
        echo "Error: Release tarball is missing core/vendor (offline Debian build needs it)"
        exit 1
    fi

    cp -r "distro/debian/$PACKAGE/debian" "$SOURCE_DIR/"
    cat > "$SOURCE_DIR/debian/changelog" <<EOF
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

    cat > "$WORK_DIR/$PACKAGE.dsc" <<EOF
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
    for old_file in $(echo "$OBS_FILES" | grep -oP '(?<=name=")[^"]*\.tar\.gz(?=")' || true); do
        case "$old_file" in
        "$SOURCE_TARBALL"|"${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"|go[0-9]*.linux-*.tar.gz)
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

osc results 2>&1 | head -10
echo ""
echo "✅ Upload complete!"
echo "Check build status with: ./distro/scripts/obs-status.sh"
