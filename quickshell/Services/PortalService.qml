pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
    id: root

    property string profileImage: ""
    property string pendingGreeterProfileUser: ""
    property int systemColorScheme: 0
    readonly property bool systemPrefersLight: systemColorScheme !== 1

    function getGreeterUserProfileImage(username) {
        if (!username) {
            profileImage = "";
            pendingGreeterProfileUser = "";
            return;
        }
        const cachedPath = GreeterUsersService.profileImagePath(username);
        if (cachedPath) {
            profileImage = cachedPath;
            pendingGreeterProfileUser = "";
            return;
        }
        pendingGreeterProfileUser = username;
        userProfileCheckProcess.command = ["bash", "-c", `uid=$(id -u ${username} 2>/dev/null) && [ -n "$uid" ] && dbus-send --system --print-reply --dest=org.freedesktop.Accounts /org/freedesktop/Accounts/User$uid org.freedesktop.DBus.Properties.Get string:org.freedesktop.Accounts.User string:IconFile 2>/dev/null | grep -oP 'string "\\K[^"]+' || echo ""`];
        userProfileCheckProcess.running = true;
    }

    Process {
        id: userProfileCheckProcess

        command: []
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const trimmed = text.trim();
                if (trimmed && !trimmed.includes("Error") && trimmed !== "/var/lib/AccountsService/icons/") {
                    root.profileImage = trimmed;
                } else {
                    root.profileImage = "";
                }
                root.pendingGreeterProfileUser = "";
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0 && root.pendingGreeterProfileUser !== "") {
                root.profileImage = "";
                root.pendingGreeterProfileUser = "";
            }
        }
    }

    Process {
        id: colorSchemeReadProcess

        command: ["gdbus", "call", "--session", "--dest", "org.freedesktop.portal.Desktop", "--object-path", "/org/freedesktop/portal/desktop", "--method", "org.freedesktop.portal.Settings.Read", "org.freedesktop.appearance", "color-scheme"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/uint32 (\d+)/);
                if (!match)
                    return;
                root.systemColorScheme = parseInt(match[1]);
            }
        }
    }
}
