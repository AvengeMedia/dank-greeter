#!/bin/bash
set -euo pipefail

# Build an SRPM for dms-greeter-git from the current checkout and upload to Copr.
# Expands the rpkg-based distro/fedora/dms-greeter-git.spec for offline rpmbuild.
#
# Usage: ./copr-upload-git.sh
# Requires: git checkout with dank-qml-common submodule initialized, rpmbuild,
#           wget/curl, and optionally copr-cli + ~/.config/copr.

PACKAGE="dms-greeter-git"
REPO="AvengeMedia/dank-greeter"
COPR_PROJECT="avengemedia/danklinux"
GO_TOOLCHAIN_VERSION="1.26.4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPEC_SRC="$REPO_ROOT/distro/fedora/${PACKAGE}.spec"

cd "$REPO_ROOT"

if [ ! -f "$SPEC_SRC" ]; then
    echo "ERROR: Spec file not found: $SPEC_SRC"
    exit 1
fi

if [ ! -e "$REPO_ROOT/dank-qml-common/DankCommon/Widgets/DankIcon.qml" ]; then
    echo "ERROR: dank-qml-common submodule missing. Run: git submodule update --init"
    exit 1
fi

BASE_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.0")"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo "0")"
COMMIT_HASH="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")"
VERSION="${BASE_VERSION}+git${COMMIT_COUNT}.${COMMIT_HASH}"
VCS_URL="$(git remote get-url origin 2>/dev/null || echo "https://github.com/${REPO}.git")"
CHANGELOG_DATE="$(date '+%a %b %d %Y')"

# RPM Source0 directory name (no '+' in path segment — keep tarball dir clean)
SRC_DIR="${PACKAGE}-${VERSION}"
# Sanitize directory name for tarball contents (rpm %setup -n)
SRC_DIR_SAFE="$(echo "$SRC_DIR" | tr '+' '_')"

echo "Building ${PACKAGE} ${VERSION} SRPM for Copr (${COPR_PROJECT})..."

mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Pack repository snapshot (include submodule content; exclude .git)
TMP_PACK="$(mktemp -d)"
trap 'rm -rf "$TMP_PACK"' EXIT

mkdir -p "$TMP_PACK/${SRC_DIR_SAFE}"
# Use git archive for tracked files, then overlay submodule tree
git archive --format=tar HEAD | tar -x -C "$TMP_PACK/${SRC_DIR_SAFE}"
rm -rf "$TMP_PACK/${SRC_DIR_SAFE}/dank-qml-common"
mkdir -p "$TMP_PACK/${SRC_DIR_SAFE}/dank-qml-common"
# Pack submodule without its .git file/dir
tar -C "$REPO_ROOT/dank-qml-common" \
    --exclude='.git' \
    -cf - . | tar -C "$TMP_PACK/${SRC_DIR_SAFE}/dank-qml-common" -xf -
# Ensure DankCommon symlink matches repo layout
rm -rf "$TMP_PACK/${SRC_DIR_SAFE}/quickshell/DankCommon"
ln -sfn ../dank-qml-common/DankCommon "$TMP_PACK/${SRC_DIR_SAFE}/quickshell/DankCommon"

TARBALL="${PACKAGE}-${VERSION}.tar.gz"
# Filename may contain '+'; use SRC_DIR_SAFE inside the archive
tar -C "$TMP_PACK" -czf ~/rpmbuild/SOURCES/"$TARBALL" "${SRC_DIR_SAFE}"

# Separate dank-qml-common tarball (matches Source3 in the rpkg spec)
tar -C "$REPO_ROOT" \
    --exclude='dank-qml-common/.git' \
    -czf ~/rpmbuild/SOURCES/dank-qml-common.tar.gz dank-qml-common

# Bundled Go toolchains
for arch in amd64 arm64; do
    GO_TGZ="go${GO_TOOLCHAIN_VERSION}.linux-${arch}.tar.gz"
    if [ ! -f ~/rpmbuild/SOURCES/"$GO_TGZ" ]; then
        echo "Downloading ${GO_TGZ}..."
        wget -q -O ~/rpmbuild/SOURCES/"$GO_TGZ" \
            "https://go.dev/dl/${GO_TGZ}"
    fi
done

# Expand rpkg macros into a plain rpmbuildable spec
EXPANDED=~/rpmbuild/SPECS/"${PACKAGE}".spec
sed \
    -e "s|%global version {{{ git_repo_version }}}|%global version ${VERSION}|" \
    -e "s|VCS:            {{{ git_repo_vcs }}}|VCS:            ${VCS_URL}|" \
    -e "s|Source0:        {{{ git_repo_pack }}}|Source0:        ${TARBALL}|" \
    -e "s|Source3:        {{{ git_pack path=\$GIT_ROOT/dank-qml-common dir_name=dank-qml-common source_name=dank-qml-common.tar.gz }}}|Source3:        dank-qml-common.tar.gz|" \
    -e "s|{{{ git_repo_setup_macro }}}|%setup -q -n ${SRC_DIR_SAFE}|" \
    "$SPEC_SRC" > "$EXPANDED"

# Replace rpkg changelog macro with a concrete entry
python3 - "$EXPANDED" "$CHANGELOG_DATE" "$VERSION" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
date, version = sys.argv[2], sys.argv[3]
text = path.read_text()
marker = "{{{ git_repo_changelog }}}"
entry = (
    f"* {date} AvengeMedia <contact@avengemedia.com> - 1:{version}-1\n"
    f"- Git snapshot build from dank-greeter ({version})\n"
)
if marker not in text:
    raise SystemExit("ERROR: git_repo_changelog macro not found in expanded spec")
path.write_text(text.replace(marker, entry))
PY

if grep -qE '\{\{\{' "$EXPANDED"; then
    echo "ERROR: Unexpanded rpkg macros remain in $EXPANDED"
    grep -nE '\{\{\{' "$EXPANDED" || true
    exit 1
fi

echo "Building SRPM..."
rpmbuild -bs "$EXPANDED"

# Version may contain '+'; match loosely
SRPM="$(ls -1 ~/rpmbuild/SRPMS/"${PACKAGE}"-*.src.rpm 2>/dev/null | tail -n 1 || true)"
if [ -z "$SRPM" ] || [ ! -f "$SRPM" ]; then
    echo "ERROR: SRPM not found for ${PACKAGE}"
    ls -la ~/rpmbuild/SRPMS/ || true
    exit 1
fi

echo "SRPM built: $SRPM"

if ! command -v copr-cli &>/dev/null; then
    echo ""
    echo "copr-cli is not installed (pip install copr-cli; configure ~/.config/copr)."
    echo "Upload manually with: copr-cli build $COPR_PROJECT $SRPM"
    exit 0
fi

echo "Uploading to Copr..."
if copr-cli build "$COPR_PROJECT" "$SRPM" --nowait; then
    echo "Build submitted: https://copr.fedorainfracloud.org/coprs/${COPR_PROJECT}/builds/"
else
    echo "ERROR: Copr upload failed. Retry with: copr-cli build $COPR_PROJECT $SRPM"
    exit 1
fi
