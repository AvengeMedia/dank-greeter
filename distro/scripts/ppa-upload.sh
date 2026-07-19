#!/bin/bash
# Build and upload the dms-greeter source package to the danklinux PPA.
# Native format: each Ubuntu series needs a distinct version, so the second
# series gets ppa suffix +1 when both are uploaded in one run.
#
# Usage: ./distro/scripts/ppa-upload.sh [series] [ppa_num] [--version=X.Y.Z] [--keep-builds]
#
# Examples:
#   ./distro/scripts/ppa-upload.sh                    # resolute (ppa1) + stonking (ppa2)
#   ./distro/scripts/ppa-upload.sh resolute           # one series, ppa1
#   ./distro/scripts/ppa-upload.sh stonking 3         # one series, rebuild ppa3
#
# CI (GitHub Actions) uploads via dput/SFTP and needs LAUNCHPAD_SSH_PRIVATE_KEY
# (plus optional LAUNCHPAD_SSH_LOGIN); local runs upload via anonymous lftp.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

REPO="AvengeMedia/dank-greeter"
PACKAGE="dms-greeter"
PPA_OWNER="avengemedia"
PPA_NAME="danklinux"
DEB_EPOCH=1
MAINTAINER="Avenge Media <AvengeMedia.US@gmail.com>"
LAUNCHPAD_API="https://api.launchpad.net/1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/distro/ubuntu/$PACKAGE"

KEEP_BUILDS=false
VERSION=""
SERIES=""
PPA_NUM=""
for arg in "$@"; do
    case "$arg" in
        --keep-builds) KEEP_BUILDS=true ;;
        --version=*)
            VERSION="${arg#*=}"
            VERSION="${VERSION#v}"
            ;;
        resolute|stonking) SERIES="$arg" ;;
        [0-9]*) PPA_NUM="$arg" ;;
        *)
            error "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

if [[ ! -d "$PACKAGE_DIR/debian" ]]; then
    error "No debian/ directory found in $PACKAGE_DIR"
    exit 1
fi

# No series given: upload both, second series ppa suffix +1 (native dual-series)
if [[ -z "$SERIES" ]]; then
    BASE_NUM="${PPA_NUM:-1}"
    EXTRA_ARGS=()
    [[ -n "$VERSION" ]] && EXTRA_ARGS+=("--version=$VERSION")
    [[ "$KEEP_BUILDS" == true ]] && EXTRA_ARGS+=("--keep-builds")
    "$0" resolute "$BASE_NUM" "${EXTRA_ARGS[@]}"
    "$0" stonking "$((BASE_NUM + 1))" "${EXTRA_ARGS[@]}"
    exit 0
fi
PPA_NUM="${PPA_NUM:-1}"

if [[ -z "$VERSION" ]]; then
    VERSION=$(git ls-remote --tags --refs --sort='-v:refname' "https://github.com/${REPO}.git" | sed -n '1s|.*/v\{0,1\}||p')
    if [[ -z "$VERSION" ]]; then
        error "Could not determine latest release tag for $REPO"
        exit 1
    fi
    info "Using latest release: $VERSION"
fi

NEW_VERSION="${DEB_EPOCH}:${VERSION}ppa${PPA_NUM}"
FILE_VERSION="${VERSION}ppa${PPA_NUM}"

info "Package: $PACKAGE -> ppa:${PPA_OWNER}/${PPA_NAME} (${SERIES}), version ${NEW_VERSION}"

published_version() {
    local series_url="https%3A%2F%2Fapi.launchpad.net%2F1.0%2Fubuntu%2F${SERIES}"
    local url="${LAUNCHPAD_API}/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}?ws.op=getPublishedSources&source_name=${PACKAGE}&status=Published&distro_series=${series_url}"
    curl -fsSL "$url" 2>/dev/null | grep -oP '"source_package_version":\s*"\K[^"]+' | head -1 || echo ""
}

PUBLISHED=$(published_version)
if [[ "$PUBLISHED" == "$NEW_VERSION" ]]; then
    warn "Version $NEW_VERSION is already published to ${PPA_NAME}/${SERIES}"
    warn "To rebuild, bump the ppa number: $0 $SERIES $((PPA_NUM + 1))"
    success "Nothing to do"
    exit 0
fi

if ! command -v debuild &>/dev/null; then
    error "debuild not found. Install devscripts."
    exit 1
fi
if ! gpg --list-secret-keys &>/dev/null; then
    error "No GPG secret keys found; source packages must be signed."
    exit 1
fi

if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
    TEMP_BASE="/tmp"
else
    TEMP_BASE="$HOME/tmp"
    mkdir -p "$TEMP_BASE"
fi
TEMP_WORK_DIR=$(mktemp -d "$TEMP_BASE/ppa_build_${PACKAGE}_XXXXXX")

cleanup() {
    if [[ "$KEEP_BUILDS" == false ]] && [[ -d "$TEMP_WORK_DIR" ]]; then
        rm -rf "$TEMP_WORK_DIR"
    fi
}
trap cleanup EXIT

info "Working directory: $TEMP_WORK_DIR"
cp -r "$PACKAGE_DIR" "$TEMP_WORK_DIR/"
WORK_PACKAGE_DIR="$TEMP_WORK_DIR/$PACKAGE"
rm -f "$WORK_PACKAGE_DIR/debian/files"
cd "$WORK_PACKAGE_DIR"

cat > debian/changelog <<EOF
${PACKAGE} (${NEW_VERSION}) ${SERIES}; urgency=medium

  * Upstream release ${VERSION}

 -- ${MAINTAINER}  $(date -R)
EOF

TARBALL_URL="https://github.com/${REPO}/releases/download/v${VERSION}/dank-greeter-${VERSION}.tar.gz"
info "Downloading release source: $TARBALL_URL"
if ! { wget -q -O dms-greeter-source.tar.gz "$TARBALL_URL" 2>/dev/null || curl -L -f -s -o dms-greeter-source.tar.gz "$TARBALL_URL"; }; then
    error "Failed to download $TARBALL_URL"
    exit 1
fi

info "Building source package..."
# -d skips build dependency checking (host may not be Ubuntu)
yes | DEBIAN_FRONTEND=noninteractive debuild -S -sa -d

CHANGES_FILE=$(find "$TEMP_WORK_DIR" -maxdepth 1 -name "${PACKAGE}_${FILE_VERSION}_source.changes" -type f | head -1)
if [[ -z "$CHANGES_FILE" ]]; then
    error "Changes file not found in $TEMP_WORK_DIR"
    exit 1
fi
success "Source package built: $(basename "$CHANGES_FILE")"

setup_launchpad_sftp() {
    if [[ -z "${LAUNCHPAD_SSH_PRIVATE_KEY:-}" ]]; then
        error "LAUNCHPAD_SSH_PRIVATE_KEY is required for CI SFTP uploads."
        exit 1
    fi

    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/launchpad_ppa"
    local login="${LAUNCHPAD_SSH_LOGIN:-$PPA_OWNER}"
    local strict_host_key_checking="yes"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    printf '%s\n' "$LAUNCHPAD_SSH_PRIVATE_KEY" > "$key_file"
    chmod 600 "$key_file"

    if ssh-keyscan -H ppa.launchpad.net >> "$ssh_dir/known_hosts" 2>/dev/null; then
        chmod 600 "$ssh_dir/known_hosts"
    else
        warn "Could not prefetch ppa.launchpad.net host key; trusting on first connection"
        strict_host_key_checking="accept-new"
    fi

    cat > "$ssh_dir/config" <<EOF
Host ppa.launchpad.net
    HostName ppa.launchpad.net
    User ${login}
    IdentityFile ${key_file}
    IdentitiesOnly yes
    StrictHostKeyChecking ${strict_host_key_checking}
EOF
    chmod 600 "$ssh_dir/config"
}

info "Uploading to PPA..."
if [[ -n "${GITHUB_ACTIONS:-}" || -n "${CI:-}" ]] && command -v dput >/dev/null 2>&1; then
    setup_launchpad_sftp
    DPUT_CONFIG=$(mktemp)
    cat >"$DPUT_CONFIG" <<EOF
[${PPA_OWNER}-${PPA_NAME}]
fqdn = ppa.launchpad.net
method = sftp
incoming = ~${PPA_OWNER}/ubuntu/${PPA_NAME}/
login = ${LAUNCHPAD_SSH_LOGIN:-$PPA_OWNER}
allow_unsigned_uploads = 0
EOF
    if dput -c "$DPUT_CONFIG" "${PPA_OWNER}-${PPA_NAME}" "$CHANGES_FILE"; then
        rm -f "$DPUT_CONFIG"
        success "Upload successful!"
    else
        rm -f "$DPUT_CONFIG"
        error "dput upload failed!"
        exit 1
    fi
else
    BUILD_DIR=$(dirname "$CHANGES_FILE")
    CHANGES_BASENAME=$(basename "$CHANGES_FILE")
    LFTP_SCRIPT=$(mktemp)
    cat >"$LFTP_SCRIPT" <<EOF
cd ~${PPA_OWNER}/ubuntu/${PPA_NAME}/
lcd $BUILD_DIR
mput ${CHANGES_BASENAME}
mput ${PACKAGE}_${FILE_VERSION}.dsc
mput ${PACKAGE}_${FILE_VERSION}.tar.xz
mput ${PACKAGE}_${FILE_VERSION}_source.buildinfo
bye
EOF
    if lftp -d ftp://anonymous:@ppa.launchpad.net <"$LFTP_SCRIPT"; then
        rm -f "$LFTP_SCRIPT"
        success "Upload successful!"
    else
        rm -f "$LFTP_SCRIPT"
        error "Upload failed!"
        exit 1
    fi
fi

echo
success "Package uploaded to ${PPA_NAME}/${SERIES}!"
info "Monitor build progress at:"
echo "  https://launchpad.net/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}/+packages"
