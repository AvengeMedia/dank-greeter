pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool isElogind: false
    property bool loginctlCommandAvailable: false
    property bool systemctlCommandAvailable: false
    property bool hibernateSupported: false

    Process {
        id: detectElogindProcess

        command: ["sh", "-c", "ps -eo comm= | grep -E '^(elogind|elogind-daemon)$'"]
        running: true

        onExited: exitCode => root.isElogind = (exitCode === 0)
    }

    Process {
        id: detectLoginctlProcess

        command: ["sh", "-c", "command -v loginctl"]
        running: true

        onExited: exitCode => root.loginctlCommandAvailable = (exitCode === 0)
    }

    Process {
        id: detectSystemctlProcess

        command: ["sh", "-c", "command -v systemctl"]
        running: true

        onExited: exitCode => root.systemctlCommandAvailable = (exitCode === 0)
    }

    Process {
        id: detectHibernateProcess

        command: ["grep", "-q", "disk", "/sys/power/state"]
        running: true

        onExited: exitCode => root.hibernateSupported = (exitCode === 0)
    }

    function powerManagerCommand(action) {
        const useLoginctl = isElogind || (loginctlCommandAvailable && !systemctlCommandAvailable);
        return [useLoginctl ? "loginctl" : "systemctl", action];
    }

    function logout() {
    }

    function suspend() {
        Quickshell.execDetached(powerManagerCommand("suspend"));
    }

    function hibernate() {
        if (!hibernateSupported)
            return;
        Quickshell.execDetached(powerManagerCommand("hibernate"));
    }

    function reboot() {
        Quickshell.execDetached(powerManagerCommand("reboot"));
    }

    function poweroff() {
        Quickshell.execDetached(powerManagerCommand("poweroff"));
    }
}
