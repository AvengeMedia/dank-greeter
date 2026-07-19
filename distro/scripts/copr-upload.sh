#!/bin/bash
set -euo pipefail

# Build the dms-greeter SRPM from the release source tarball and upload to Copr
# Usage: ./copr-upload.sh [VERSION] [RELEASE]
# Examples:
#   ./copr-upload.sh              # latest GitHub release, release 1
#   ./copr-upload.sh 1.0.0 2     # explicit version, rebuild release 2

PACKAGE="dms-greeter"
REPO="AvengeMedia/dank-greeter"
COPR_PROJECT="avengemedia/danklinux"
VERSION="${1:-}"
RELEASE="${2:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -z "$VERSION" ]; then
    echo "Determining latest version..."
    VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
        echo "ERROR: Failed to determine version. Please specify manually."
        exit 1
    fi
    echo "Using latest version: $VERSION"
fi

echo "Building ${PACKAGE} v${VERSION}-${RELEASE} SRPM for Copr..."

mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

TARBALL="dank-greeter-${VERSION}.tar.gz"
if [ ! -f ~/rpmbuild/SOURCES/"$TARBALL" ]; then
    echo "Downloading source tarball for v${VERSION}..."
    wget -O ~/rpmbuild/SOURCES/"$TARBALL" \
        "https://github.com/${REPO}/releases/download/v${VERSION}/${TARBALL}" || {
        echo "ERROR: Failed to download $TARBALL for v${VERSION}"
        exit 1
    }
fi

SPEC_FILE="$REPO_ROOT/distro/fedora/${PACKAGE}.spec"
if [ ! -f "$SPEC_FILE" ]; then
    echo "ERROR: Spec file not found: $SPEC_FILE"
    exit 1
fi

cp "$SPEC_FILE" ~/rpmbuild/SPECS/"${PACKAGE}".spec

CHANGELOG_DATE="$(date '+%a %b %d %Y')"
sed -i "s/VERSION_PLACEHOLDER/${VERSION}/g" ~/rpmbuild/SPECS/"${PACKAGE}".spec
sed -i "s/RELEASE_PLACEHOLDER/${RELEASE}/g" ~/rpmbuild/SPECS/"${PACKAGE}".spec
sed -i "s/CHANGELOG_DATE_PLACEHOLDER/${CHANGELOG_DATE}/g" ~/rpmbuild/SPECS/"${PACKAGE}".spec

echo "Building SRPM..."
cd ~/rpmbuild/SPECS
rpmbuild -bs "${PACKAGE}".spec

SRPM=$(ls ~/rpmbuild/SRPMS/"${PACKAGE}"-"${VERSION}"-*.src.rpm | tail -n 1)
if [ ! -f "$SRPM" ]; then
    echo "ERROR: SRPM not found (expected ${PACKAGE}-${VERSION}-*.src.rpm)"
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
