#!/usr/bin/env bash
# OBS build status for dms-greeter (all repos/arches); pulls logs on failure.
# Usage: ./distro/scripts/obs-status.sh

OBS_PROJECT="home:AvengeMedia:danklinux"
PACKAGE="dms-greeter"
OBS_BASE="$HOME/.cache/osc-checkouts"

REPOS=("Debian_13" "openSUSE_Tumbleweed" "16.0")
ARCHES=("x86_64" "aarch64")

mkdir -p "$OBS_BASE"
cd "$OBS_BASE" || exit 1

if [[ ! -d "$OBS_PROJECT/$PACKAGE" ]]; then
    osc co "$OBS_PROJECT/$PACKAGE" 2>&1 | tail -1
fi

cd "$OBS_PROJECT/$PACKAGE" || exit 1

ALL_RESULTS=$(osc results 2>&1)

FAILED_BUILDS=()
for repo in "${REPOS[@]}"; do
    for arch in "${ARCHES[@]}"; do
        STATUS=$(echo "$ALL_RESULTS" | grep "$repo.*$arch" | awk '{print $NF}' | head -1)
        [[ -n "$STATUS" ]] || continue

        case "$STATUS" in
        succeeded)
            SYMBOL="✅"
            ;;
        failed|broken*)
            SYMBOL="❌"
            FAILED_BUILDS+=("$repo $arch")
            ;;
        blocked)
            SYMBOL="⏸️"
            ;;
        unresolvable)
            SYMBOL="⚠️"
            ;;
        *)
            SYMBOL="⏳"
            ;;
        esac
        echo "  $SYMBOL $repo $arch: $STATUS"
    done
done

if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
    echo ""
    echo "Fetching logs for failed builds..."
    for build in "${FAILED_BUILDS[@]}"; do
        read -r repo arch <<<"$build"
        echo ""
        echo "──────────────────────────────────────────"
        echo "Build log: $repo $arch"
        echo "──────────────────────────────────────────"
        osc remotebuildlog "$OBS_PROJECT" "$PACKAGE" "$repo" "$arch" 2>&1 | tail -100
    done
fi
