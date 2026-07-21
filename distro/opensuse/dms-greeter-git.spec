# Spec for DMS Greeter - OpenSUSE/OBS git snapshots
# Package name is dms-greeter-git so it can coexist in home:AvengeMedia:danklinux
# beside stable dms-greeter. Mutual Conflicts only — never Obsoletes stable
# (same-repo Obsoletes would auto-replace stable on zypper up / dnf update).
# OBS builds are offline: Go dependencies come vendored in the source tarball
# and the Go toolchain is bundled as Source1/Source2 (staged by obs-upload.sh).

%global debug_package %{nil}
%global go_toolchain_version 1.26.4
%global pkg_summary DMS Greeter for greetd (git)

Name:           dms-greeter-git
Epoch:          2
Version:        0.0.0+git0.00000000
Release:        1%{?dist}
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/AvengeMedia/dank-greeter

Source0:        dms-greeter-git-source.tar.gz
Source1:        go%{go_toolchain_version}.linux-amd64.tar.gz
Source2:        go%{go_toolchain_version}.linux-arm64.tar.gz

BuildRequires:  make
BuildRequires:  systemd-rpm-macros

Requires:       greetd
Requires:       (quickshell-git or quickshell)
Requires(post): /usr/sbin/useradd
Requires(post): /usr/sbin/groupadd

Provides:       dms-greeter = %{epoch}:%{version}-%{release}
Conflicts:      dms-greeter

Recommends:     acl
Suggests:       niri
Suggests:       hyprland
Suggests:       sway

%description
DMS Greeter is a greetd login screen with the Dank Material aesthetic.
This git package builds from the tip of the dank-greeter repository.
A single Go binary with the Quickshell UI embedded; the UI is extracted
to the greeter cache directory at startup.

Supports multiple compositors including Niri, Hyprland, and Sway with
session selection, user authentication, and dynamic theming synced from
DankMaterialShell.

Conflicts with the stable dms-greeter package; both install /usr/bin/dms-greeter.
Switch explicitly (e.g. zypper remove dms-greeter && zypper install dms-greeter-git).

%prep
%setup -q -n dms-greeter-git-source
test -d core/vendor || { echo "ERROR: vendored Go dependencies missing from source tarball"; exit 1; }
# Ensure DankCommon submodule content is present (packed by obs-upload.sh)
test -e quickshell/DankCommon/Widgets/DankIcon.qml || { echo "ERROR: DankCommon missing from source tarball"; exit 1; }

%build
case "%{_arch}" in
  x86_64)
    GO_TARBALL="%{_sourcedir}/go%{go_toolchain_version}.linux-amd64.tar.gz"
    ;;
  aarch64)
    GO_TARBALL="%{_sourcedir}/go%{go_toolchain_version}.linux-arm64.tar.gz"
    ;;
  *)
    echo "Unsupported architecture for bundled Go: %{_arch}"
    exit 1
    ;;
esac

rm -rf "%{_builddir}/go-bootstrap" "%{_builddir}/.go-toolchain"
mkdir -p "%{_builddir}/go-bootstrap"
tar -xzf "$GO_TARBALL" -C "%{_builddir}/go-bootstrap"
mv "%{_builddir}/go-bootstrap/go" "%{_builddir}/.go-toolchain"

export GOROOT="%{_builddir}/.go-toolchain"
export PATH="$GOROOT/bin:$PATH"

export HOME=%{_builddir}/go-home
export GOCACHE=%{_builddir}/go-cache
export GOMODCACHE=%{_builddir}/go-mod
mkdir -p $HOME $GOCACHE $GOMODCACHE

export GOTOOLCHAIN=local
export GOFLAGS=-mod=vendor

go version

# Pin go.mod and vendor/modules.txt to the bundled Go toolchain version
sed -i "s/^go [0-9]\+\.[0-9]\+\(\.[0-9]*\)\?$/go %{go_toolchain_version}/" core/go.mod
sed -i "s/^\(## explicit; go \)[0-9]\+\.[0-9]\+\(\.[0-9]*\)\?$/\1%{go_toolchain_version}/" core/vendor/modules.txt

VERSION="%{version}"
COMMIT=$(echo "%{version}" | grep -oP '(?<=git)[0-9]+\.[a-f0-9]+' | cut -d. -f2 | head -c8 || echo "unknown")
make -C core build VERSION="$VERSION" COMMIT="$COMMIT"

%install
install -Dm755 core/bin/dms-greeter %{buildroot}%{_bindir}/dms-greeter

install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
core/bin/dms-greeter completion bash > %{buildroot}%{_datadir}/bash-completion/completions/dms-greeter
core/bin/dms-greeter completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_dms-greeter
core/bin/dms-greeter completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/dms-greeter.fish

install -Dpm0644 assets/systemd/sysusers-dms-greeter.conf %{buildroot}%{_sysusersdir}/dms-greeter.conf
install -Dpm0644 assets/systemd/tmpfiles-dms-greeter.conf %{buildroot}%{_tmpfilesdir}/dms-greeter.conf

install -Dm644 LICENSE %{buildroot}%{_docdir}/dms-greeter/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/dms-greeter/README.md
install -d %{buildroot}%{_docdir}/dms-greeter/examples
install -m644 assets/examples/* %{buildroot}%{_docdir}/dms-greeter/examples/

install -dm755 %{buildroot}%{_sharedstatedir}/greeter
install -dm750 %{buildroot}%{_localstatedir}/cache/dms-greeter

%files
%dir %{_docdir}/dms-greeter
%license %{_docdir}/dms-greeter/LICENSE
%doc %{_docdir}/dms-greeter/README.md
%doc %{_docdir}/dms-greeter/examples
%{_bindir}/dms-greeter
%{_datadir}/bash-completion/completions/dms-greeter
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_dms-greeter
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/dms-greeter.fish
%{_sysusersdir}/dms-greeter.conf
%{_tmpfilesdir}/dms-greeter.conf
%dir %attr(0755,greeter,greeter) %{_sharedstatedir}/greeter
%dir %attr(0750,greeter,greeter) %{_localstatedir}/cache/dms-greeter

%pre
# Create greeter user/group if they don't exist
getent group greeter >/dev/null || groupadd -r greeter
getent passwd greeter >/dev/null || \
    useradd -r -g greeter -d %{_sharedstatedir}/greeter -s /bin/bash \
    -c "System Greeter" greeter
exit 0

%post
# SELinux contexts (no-op on OpenSUSE - semanage/restorecon not present)
if [ -x /usr/sbin/semanage ] && [ -x /usr/sbin/restorecon ]; then
    semanage fcontext -a -t bin_t '%{_bindir}/dms-greeter' >/dev/null 2>&1 || true
    restorecon %{_bindir}/dms-greeter >/dev/null 2>&1 || true
    semanage fcontext -a -t user_home_dir_t '%{_sharedstatedir}/greeter(/.*)?' >/dev/null 2>&1 || true
    restorecon -R %{_sharedstatedir}/greeter >/dev/null 2>&1 || true
    semanage fcontext -a -t cache_home_t '%{_localstatedir}/cache/dms-greeter(/.*)?' >/dev/null 2>&1 || true
    restorecon -R %{_localstatedir}/cache/dms-greeter >/dev/null 2>&1 || true
    restorecon %{_sysconfdir}/pam.d/greetd >/dev/null 2>&1 || true
fi

# Resolve greeter runtime account/group for distro differences
GREETER_USER="greeter"
for candidate in greeter greetd _greeter; do
    if getent passwd "$candidate" >/dev/null 2>&1; then
        GREETER_USER="$candidate"
        break
    fi
done

GREETER_GROUP="$GREETER_USER"
if ! getent group "$GREETER_GROUP" >/dev/null 2>&1; then
    for candidate in greeter greetd _greeter; do
        if getent group "$candidate" >/dev/null 2>&1; then
            GREETER_GROUP="$candidate"
            break
        fi
    done
fi

# Ensure proper ownership of greeter directories
chown -R "$GREETER_USER:$GREETER_GROUP" %{_localstatedir}/cache/dms-greeter 2>/dev/null || true
chown -R "$GREETER_USER:$GREETER_GROUP" %{_sharedstatedir}/greeter 2>/dev/null || true

# Verify PAM configuration
PAM_CONFIG="/etc/pam.d/greetd"
write_greetd_pam_config() {
    # openSUSE and Debian families usually expose PAM stacks as common-*
    if [ -f /etc/pam.d/common-auth ] && [ -f /etc/pam.d/common-account ] && [ -f /etc/pam.d/common-password ] && [ -f /etc/pam.d/common-session ]; then
        cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       include     common-auth
account    required    pam_nologin.so
account    include     common-account
password   include     common-password
session    required    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     common-session
PAM_EOF
        return
    fi

    # Fedora/RHEL style system-auth/postlogin stack
    if [ -f /etc/pam.d/system-auth ]; then
        if [ -f /etc/pam.d/postlogin ]; then
            cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       substack    system-auth
auth       include     postlogin
account    required    pam_nologin.so
account    include     system-auth
password   include     system-auth
session    required    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     system-auth
session    include     postlogin
PAM_EOF
        else
            cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       include     system-auth
account    required    pam_nologin.so
account    include     system-auth
password   include     system-auth
session    required    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     system-auth
PAM_EOF
        fi
        return
    fi

    # Last-resort conservative fallback
    cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       required    pam_unix.so nullok
account    required    pam_unix.so
password   required    pam_unix.so nullok sha512
session    required    pam_unix.so
PAM_EOF
}

if [ ! -f "$PAM_CONFIG" ]; then
    write_greetd_pam_config
    chmod 644 "$PAM_CONFIG"
    [ "$1" -eq 1 ] && echo "Created PAM configuration for greetd"
else
    NEEDS_PAM_UPDATE=0
    if grep -q "common-auth" "$PAM_CONFIG"; then
        if [ ! -f /etc/pam.d/common-auth ]; then
            NEEDS_PAM_UPDATE=1
        fi
    elif grep -q "system-auth" "$PAM_CONFIG"; then
        if [ ! -f /etc/pam.d/system-auth ]; then
            NEEDS_PAM_UPDATE=1
        fi
    else
        NEEDS_PAM_UPDATE=1
    fi

    if [ "$NEEDS_PAM_UPDATE" -eq 1 ]; then
        cp "$PAM_CONFIG" "$PAM_CONFIG.backup-dms-greeter"
        write_greetd_pam_config
        chmod 644 "$PAM_CONFIG"
        [ "$1" -eq 1 ] && echo "Updated PAM configuration (old config backed up to $PAM_CONFIG.backup-dms-greeter)"
    fi
fi

# Auto-configure greetd config
GREETD_CONFIG="/etc/greetd/config.toml"
CONFIG_STATUS="Not modified (already configured)"

COMPOSITOR=""
for candidate in niri Hyprland sway; do
    if command -v "$candidate" >/dev/null 2>&1; then
        case "$candidate" in
            Hyprland)
                COMPOSITOR="hyprland"
                ;;
            *)
                COMPOSITOR="$candidate"
                ;;
        esac
        break
    fi
done

if [ ! -f "$GREETD_CONFIG" ]; then
    mkdir -p /etc/greetd
    if [ -n "$COMPOSITOR" ]; then
        cat > "$GREETD_CONFIG" << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "GREETER_USER_PLACEHOLDER"
command = "/usr/bin/dms-greeter --command COMPOSITOR_PLACEHOLDER"
GREETD_EOF
        sed -i "s|GREETER_USER_PLACEHOLDER|$GREETER_USER|" "$GREETD_CONFIG"
        sed -i "s|COMPOSITOR_PLACEHOLDER|$COMPOSITOR|" "$GREETD_CONFIG"
        CONFIG_STATUS="Created new config with $COMPOSITOR ✓"
    else
        cat > "$GREETD_CONFIG" << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "GREETER_USER_PLACEHOLDER"
command = "agreety --cmd /bin/login"
GREETD_EOF
        sed -i "s|GREETER_USER_PLACEHOLDER|$GREETER_USER|" "$GREETD_CONFIG"
        CONFIG_STATUS="Created safe fallback config (no supported compositor detected)"
    fi
elif ! grep -q "dms-greeter" "$GREETD_CONFIG"; then
    if [ -n "$COMPOSITOR" ]; then
        BACKUP_FILE="${GREETD_CONFIG}.backup-$(date +%%Y%%m%%d-%%H%%M%%S)"
        cp "$GREETD_CONFIG" "$BACKUP_FILE" 2>/dev/null || true
        sed -i "/^\[default_session\]/,/^\[/ s|^command =.*|command = \"/usr/bin/dms-greeter --command $COMPOSITOR\"|" "$GREETD_CONFIG"
        sed -i "/^\[default_session\]/,/^\[/ s|^user =.*|user = \"$GREETER_USER\"|" "$GREETD_CONFIG"
        CONFIG_STATUS="Updated existing config (backed up) with $COMPOSITOR ✓"
    else
        CONFIG_STATUS="Skipped dms-greeter command update (no supported compositor detected)"
    fi
fi

# Set graphical.target as default
CURRENT_TARGET=$(systemctl get-default 2>/dev/null || echo "unknown")
if [ "$CURRENT_TARGET" != "graphical.target" ]; then
    systemctl set-default graphical.target >/dev/null 2>&1 || true
    TARGET_STATUS="Set to graphical.target (was: $CURRENT_TARGET) ✓"
else
    TARGET_STATUS="Already graphical.target ✓"
fi

if [ "$1" -eq 1 ]; then
cat << 'EOF'

=========================================================================
        DMS Greeter (git) Installation Complete!
=========================================================================

Status:
EOF
echo "    ✓ Greetd config: $CONFIG_STATUS"
echo "    ✓ Default target: $TARGET_STATUS"
cat << 'EOF'
    ✓ Greeter user: Created
    ✓ Greeter directories: /var/cache/dms-greeter, /var/lib/greeter
    ✓ SELinux contexts: Applied (if applicable)

Next steps:

1. Enable the greeter:
     dms-greeter enable

2. Sync your theme with the greeter (optional):
     dms-greeter sync

Ready to test? Run: sudo systemctl start greetd
Documentation: https://danklinux.com/docs/dankgreeter/
=========================================================================

EOF
fi

%postun
if [ "$1" -eq 0 ] && [ -x /usr/sbin/semanage ]; then
    semanage fcontext -d '%{_bindir}/dms-greeter' 2>/dev/null || true
    semanage fcontext -d '%{_sharedstatedir}/greeter(/.*)?' 2>/dev/null || true
    semanage fcontext -d '%{_localstatedir}/cache/dms-greeter(/.*)?' 2>/dev/null || true
fi

%changelog
* Mon Jul 20 2026 AvengeMedia <contact@avengemedia.com> - 1:0.0.0+git0.00000000-1
- Git snapshot packaging for dank-greeter (version rewritten by obs-upload.sh)
