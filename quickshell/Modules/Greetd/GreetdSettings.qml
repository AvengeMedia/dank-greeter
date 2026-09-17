pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "GreetdEnv.js" as GreetdEnv

Singleton {
    id: root
    readonly property var log: Log.scoped("GreetdSettings")

    readonly property var _envRememberLastSession: GreetdEnv.readBoolOverride(Quickshell.env, ["DMS_GREET_REMEMBER_LAST_SESSION", "DMS_SAVE_SESSION"], undefined, log)
    readonly property var _envRememberLastUser: GreetdEnv.readBoolOverride(Quickshell.env, ["DMS_GREET_REMEMBER_LAST_USER", "DMS_SAVE_USERNAME"], undefined, log)

    readonly property bool settingsLoaded: SettingsData.loaded
    readonly property bool rememberLastSession: _envRememberLastSession !== undefined ? _envRememberLastSession : SettingsData.greeterRememberLastSession
    readonly property bool rememberLastUser: _envRememberLastUser !== undefined ? _envRememberLastUser : SettingsData.greeterRememberLastUser

    property string configHomeDir: ""

    function setConfigBaseDir(dir, homeDir) {
        configHomeDir = homeDir || "";
        SettingsData.setConfigBaseDir(dir);
    }

    function resetConfigBaseDir() {
        setConfigBaseDir("", "");
    }

    function resolveUserPath(path) {
        if (!path || !configHomeDir)
            return Paths.expandTilde(path || "");
        if (path === "~")
            return configHomeDir;
        if (path.startsWith("~/"))
            return configHomeDir + path.substring(1);
        if (path.startsWith("/"))
            return path;
        return configHomeDir + "/" + path;
    }
}
