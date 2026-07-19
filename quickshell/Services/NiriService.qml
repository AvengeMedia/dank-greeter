pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.DankCommon.Common as DankCommon
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("NiriService")

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property bool niriAvailable: CompositorService.isNiri && socketPath.length > 0

    property var keyboardLayoutNames: []
    property int currentKeyboardLayoutIndex: 0

    DankCommon.DankSocket {
        id: eventStreamSocket

        path: root.socketPath
        connected: root.niriAvailable

        onConnectionStateChanged: {
            if (linkUp)
                send('"EventStream"');
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    root.handleNiriEvent(JSON.parse(line));
                } catch (e) {
                    root.log.warn("Failed to parse event:", line, e);
                }
            }
        }
    }

    DankCommon.DankSocket {
        id: requestSocket

        path: root.socketPath
        connected: root.niriAvailable
    }

    function handleNiriEvent(event) {
        const eventType = Object.keys(event)[0];
        switch (eventType) {
        case "KeyboardLayoutsChanged":
            keyboardLayoutNames = event.KeyboardLayoutsChanged.keyboard_layouts.names;
            currentKeyboardLayoutIndex = event.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
            break;
        case "KeyboardLayoutSwitched":
            currentKeyboardLayoutIndex = event.KeyboardLayoutSwitched.idx;
            break;
        }
    }

    function send(request) {
        if (!niriAvailable || !requestSocket.linkUp)
            return false;
        requestSocket.send(request);
        return true;
    }

    function getCurrentKeyboardLayoutName() {
        if (currentKeyboardLayoutIndex >= 0 && currentKeyboardLayoutIndex < keyboardLayoutNames.length)
            return keyboardLayoutNames[currentKeyboardLayoutIndex];
        return "";
    }

    function cycleKeyboardLayout() {
        return send({
            "Action": {
                "SwitchLayout": {
                    "layout": "Next"
                }
            }
        });
    }
}
