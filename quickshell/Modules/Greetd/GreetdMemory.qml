pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "GreetdEnv.js" as GreetdEnv
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("GreetdMemory")

    readonly property string greetCfgDir: Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter"
    readonly property string memoryFile: greetCfgDir + "/.local/state/memory.json"
    readonly property bool rememberLastSession: GreetdEnv.readBoolOverride(Quickshell.env, ["DMS_GREET_REMEMBER_LAST_SESSION", "DMS_SAVE_SESSION"], true, log)
    readonly property bool rememberLastUser: GreetdEnv.readBoolOverride(Quickshell.env, ["DMS_GREET_REMEMBER_LAST_USER", "DMS_SAVE_USERNAME"], true, log)

    property string lastSessionId: ""
    property string lastSessionDesktopId: ""
    property string lastSuccessfulUser: ""
    property bool memoryReady: false

    Component.onCompleted: {
        parseMemory(memoryFileView.text());
    }

    function parseMemory(content) {
        try {
            if (!content || !content.trim())
                return;
            const memory = JSON.parse(content);
            lastSessionId = rememberLastSession ? (memory.lastSessionId || "") : "";
            lastSessionDesktopId = rememberLastSession ? (memory.lastSessionDesktopId || "") : "";
            lastSuccessfulUser = rememberLastUser ? (memory.lastSuccessfulUser || "") : "";
            if (!rememberLastSession || !rememberLastUser)
                saveMemory();
        } catch (e) {
            log.warn("Failed to parse greetd memory:", e);
        }
    }

    function saveMemory() {
        let memory = {};
        if (rememberLastSession && lastSessionId)
            memory.lastSessionId = lastSessionId;
        if (rememberLastSession && lastSessionDesktopId)
            memory.lastSessionDesktopId = lastSessionDesktopId;
        if (rememberLastUser && lastSuccessfulUser)
            memory.lastSuccessfulUser = lastSuccessfulUser;
        memoryFileView.setText(JSON.stringify(memory, null, 2));
    }

    function setLastSession(id, desktopId) {
        if (!rememberLastSession) {
            if (lastSessionId !== "" || lastSessionDesktopId !== "") {
                lastSessionId = "";
                lastSessionDesktopId = "";
                saveMemory();
            }
            return;
        }
        lastSessionId = id || "";
        lastSessionDesktopId = desktopId || "";
        if (!lastSessionId)
            lastSessionDesktopId = "";
        saveMemory();
    }

    function setLastSuccessfulUser(username) {
        if (!rememberLastUser) {
            if (lastSuccessfulUser !== "") {
                lastSuccessfulUser = "";
                saveMemory();
            }
            return;
        }
        lastSuccessfulUser = username || "";
        saveMemory();
    }

    FileView {
        id: memoryFileView
        path: root.memoryFile
        blockLoading: false
        blockWrites: false
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onLoaded: {
            parseMemory(memoryFileView.text());
            root.memoryReady = true;
        }
        onLoadFailed: {
            root.memoryReady = true;
        }
    }
}
