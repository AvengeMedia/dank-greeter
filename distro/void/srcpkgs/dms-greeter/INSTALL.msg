dms-greeter installed: a single Go binary with the quickshell UI embedded.
It replaces the previous bash wrapper and the /usr/share/quickshell/dms-greeter
tree; existing /etc/greetd/config.toml entries keep working:

    command = "/usr/bin/dms-greeter --command COMPOSITOR"

Void needs the pieces logind would handle on systemd: enable seatd, add the
_greeter user to the seat/video/input groups, and add pam_rundir to the greetd
PAM stack. With DankMaterialShell installed, `dms greeter enable` sets all of
this up. Sync your shell theme into the greeter with:

    dms-greeter sync

Requirements not pulled in automatically: a Wayland compositor (niri, hyprland,
sway, …) and a working DRM device (/dev/dri/card*; in a VM, enable virtio-gpu).
