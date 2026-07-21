#!/bin/bash
set -euo pipefail

# Build SRPM and upload to Copr (avengemedia/danklinux).
# Stable: release tarball from GitHub. Git: current checkout + submodule.
#
# Usage:
#   ./distro/scripts/copr-upload.sh [dms-greeter|dms-greeter-git] [VERSION] [RELEASE]
#
# Examples:
#   ./distro/scripts/copr-upload.sh                         # stable, latest release, release 1
#   ./distro/scripts/copr-upload.sh dms-greeter 1.0.0 2    # stable, explicit version/rebuild
#   ./distro/scripts/copr-upload.sh dms-greeter-git        # git snapshot from HEAD (release 1)
#   ./distro/scripts/copr-upload.sh dms-greeter-git 2      # git snapshot, RPM release 2 (same commit rebuild)

REPO="AvengeMedia/dank-greeter"
COPR_PROJECT="avengemedia/danklinux"

PACKAGE="dms-greeter"
VERSION=""
RELEASE="1"

for arg in "$@"; do
    case "$arg" in
    dms-greeter|dms-greeter-git)
        PACKAGE="$arg"
        ;;
    "")
        ;;
    *)
        # Dotted → stable version; bare integer → release number
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
            RELEASE="$arg"
        else
            VERSION="$arg"
        fi
        ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

SPEC_SRC="$REPO_ROOT/distro/fedora/${PACKAGE}.spec"
if [[ ! -f "$SPEC_SRC" ]]; then
    echo "ERROR: Spec file not found: $SPEC_SRC"
    exit 1
fi

mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

upload_srpm() {
    local srpm="$1"
    echo "SRPM built: $srpm"

    if ! command -v copr-cli &>/dev/null; then
        echo ""
        echo "copr-cli is not installed (pip install copr-cli; configure ~/.config/copr)."
        echo "Upload manually with: copr-cli build $COPR_PROJECT $srpm"
        exit 0
    fi

    echo "Uploading to Copr..."
    if copr-cli build "$COPR_PROJECT" "$srpm" --nowait; then
        echo "Build submitted: https://copr.fedorainfracloud.org/coprs/${COPR_PROJECT}/builds/"
    else
        echo "ERROR: Copr upload failed. Retry with: copr-cli build $COPR_PROJECT $srpm"
        exit 1
    fi
}

build_stable() {
    if [[ -z "$VERSION" ]]; then
        echo "Determining latest version..."
        VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
        if [[ -z "$VERSION" ]] || [[ "$VERSION" == "null" ]]; then
            echo "ERROR: Failed to determine version. Please specify manually."
            exit 1
        fi
        echo "Using latest version: $VERSION"
    fi

    echo "Building ${PACKAGE} v${VERSION}-${RELEASE} SRPM for Copr..."

    local tarball="dank-greeter-${VERSION}.tar.gz"
    if [[ ! -f ~/rpmbuild/SOURCES/"$tarball" ]]; then
        echo "Downloading source tarball for v${VERSION}..."
        wget -O ~/rpmbuild/SOURCES/"$tarball" \
            "https://github.com/${REPO}/releases/download/v${VERSION}/${tarball}" || {
            echo "ERROR: Failed to download $tarball for v${VERSION}"
            exit 1
        }
    fi

    cp "$SPEC_SRC" ~/rpmbuild/SPECS/"${PACKAGE}".spec
    local changelog_date
    changelog_date="$(date '+%a %b %d %Y')"
    sed -i "s/VERSION_PLACEHOLDER/${VERSION}/g" ~/rpmbuild/SPECS/"${PACKAGE}".spec
    sed -i "s/RELEASE_PLACEHOLDER/${RELEASE}/g" ~/rpmbuild/SPECS/"${PACKAGE}".spec
    sed -i "s/CHANGELOG_DATE_PLACEHOLDER/${changelog_date}/g" ~/rpmbuild/SPECS/"${PACKAGE}".spec

    echo "Building SRPM..."
    (cd ~/rpmbuild/SPECS && rpmbuild -bs "${PACKAGE}".spec)

    # Prefer newest by mtime — alphabetical ls picks older gitN (git9 > git14).
    local srpm
    srpm=$(ls -1t ~/rpmbuild/SRPMS/"${PACKAGE}"-"${VERSION}"-*.src.rpm 2>/dev/null | head -n 1 || true)
    if [[ -z "$srpm" ]] || [[ ! -f "$srpm" ]]; then
        echo "ERROR: SRPM not found (expected ${PACKAGE}-${VERSION}-*.src.rpm)"
        ls -la ~/rpmbuild/SRPMS/ || true
        exit 1
    fi
    upload_srpm "$srpm"
}

build_git() {
    if [[ ! -e "$REPO_ROOT/dank-qml-common/DankCommon/Widgets/DankIcon.qml" ]]; then
        echo "ERROR: dank-qml-common submodule missing. Run: git submodule update --init"
        exit 1
    fi

    local base_version commit_count commit_hash version vcs_url changelog_date
    base_version="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    [[ -z "$base_version" ]] && base_version="1.0.0"
    commit_count="$(git rev-list --count HEAD 2>/dev/null || echo "0")"
    commit_hash="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")"
    version="${base_version}+git${commit_count}.${commit_hash}"
    vcs_url="$(git remote get-url origin 2>/dev/null || echo "https://github.com/${REPO}.git")"
    changelog_date="$(date '+%a %b %d %Y')"

    local src_dir_safe go_ver
    src_dir_safe="$(echo "${PACKAGE}-${version}" | tr '+' '_')"
    go_ver="$(grep -m1 '^go ' "$REPO_ROOT/core/go.mod" | awk '{print $2}')"
    if [[ -z "$go_ver" ]]; then
        echo "ERROR: Could not determine Go version from core/go.mod"
        exit 1
    fi

    echo "Building ${PACKAGE} ${version}-${RELEASE} SRPM for Copr (${COPR_PROJECT})..."

    local tmp_pack
    tmp_pack="$(mktemp -d)"
    # Expand path now — EXIT trap runs after locals are gone (set -u).
    trap 'rm -rf "'"$tmp_pack"'"' EXIT

    mkdir -p "$tmp_pack/${src_dir_safe}"
    git archive --format=tar HEAD | tar -x -C "$tmp_pack/${src_dir_safe}"
    rm -rf "$tmp_pack/${src_dir_safe}/dank-qml-common"
    mkdir -p "$tmp_pack/${src_dir_safe}/dank-qml-common"
    tar -C "$REPO_ROOT/dank-qml-common" --exclude='.git' -cf - . \
        | tar -C "$tmp_pack/${src_dir_safe}/dank-qml-common" -xf -
    rm -rf "$tmp_pack/${src_dir_safe}/quickshell/DankCommon"
    ln -sfn ../dank-qml-common/DankCommon "$tmp_pack/${src_dir_safe}/quickshell/DankCommon"

    local tarball="${PACKAGE}-${version}.tar.gz"
    tar -C "$tmp_pack" -czf ~/rpmbuild/SOURCES/"$tarball" "${src_dir_safe}"
    rm -rf "$tmp_pack"
    trap - EXIT

    tar -C "$REPO_ROOT" \
        --exclude='dank-qml-common/.git' \
        -czf ~/rpmbuild/SOURCES/dank-qml-common.tar.gz dank-qml-common

    local arch go_tgz
    for arch in amd64 arm64; do
        go_tgz="go${go_ver}.linux-${arch}.tar.gz"
        if [[ ! -f ~/rpmbuild/SOURCES/"$go_tgz" ]]; then
            echo "Downloading ${go_tgz}..."
            wget -q -O ~/rpmbuild/SOURCES/"$go_tgz" "https://go.dev/dl/${go_tgz}"
        fi
    done

    local expanded=~/rpmbuild/SPECS/"${PACKAGE}".spec
    sed \
        -e "s|%global version {{{ git_repo_version }}}|%global version ${version}|" \
        -e "s|%global go_toolchain_version .*|%global go_toolchain_version ${go_ver}|" \
        -e "s|VCS:            {{{ git_repo_vcs }}}|VCS:            ${vcs_url}|" \
        -e "s|Source0:        {{{ git_repo_pack }}}|Source0:        ${tarball}|" \
        -e "s|Source3:        {{{ git_pack path=\$GIT_ROOT/dank-qml-common dir_name=dank-qml-common source_name=dank-qml-common.tar.gz }}}|Source3:        dank-qml-common.tar.gz|" \
        -e "s|{{{ git_repo_setup_macro }}}|%setup -q -n ${src_dir_safe}|" \
        -e "s|RELEASE_PLACEHOLDER|${RELEASE}|g" \
        "$SPEC_SRC" > "$expanded"

    python3 - "$expanded" "$changelog_date" "$version" "$RELEASE" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
date, version, release = sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text()
marker = "{{{ git_repo_changelog }}}"
entry = (
    f"* {date} AvengeMedia <contact@avengemedia.com> - 2:{version}-{release}\n"
    f"- Git snapshot build from dank-greeter ({version})\n"
)
if marker not in text:
    raise SystemExit("ERROR: git_repo_changelog macro not found in expanded spec")
path.write_text(text.replace(marker, entry))
PY

    if grep -qE '\{\{\{' "$expanded"; then
        echo "ERROR: Unexpanded rpkg macros remain in $expanded"
        grep -nE '\{\{\{' "$expanded" || true
        exit 1
    fi

    echo "Building SRPM..."
    local rpmbuild_out srpm
    rpmbuild_out="$(rpmbuild -bs "$expanded")"
    printf '%s\n' "$rpmbuild_out"
    srpm="$(printf '%s\n' "$rpmbuild_out" | sed -n 's/^Wrote: //p' | tail -n 1)"
    if [[ -z "$srpm" ]] || [[ ! -f "$srpm" ]]; then
        # Fallback: newest by mtime (alphabetical ls picks older gitN wrongly)
        srpm="$(ls -1t ~/rpmbuild/SRPMS/"${PACKAGE}"-*.src.rpm 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -z "$srpm" ]] || [[ ! -f "$srpm" ]]; then
        echo "ERROR: SRPM not found for ${PACKAGE}"
        ls -la ~/rpmbuild/SRPMS/ || true
        exit 1
    fi
    upload_srpm "$srpm"
}

if [[ "$PACKAGE" == *-git ]]; then
    build_git
else
    build_stable
fi
