pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Session

FocusScope {
    id: root

    required property string screenName
    property var lockHost: null

    readonly property var screen: Quickshell.screens.find(s => s.name === screenName) ?? null
    readonly property string screenKey: SettingsData.getScreenDisplayName(screen)
    readonly property var supportedTypes: ["desktopClock", "lockDate", "lockAuth", "lockStatus", "lockPower", "greeterSession"]
    readonly property var instances: (SettingsData.greeterWidgetInstances || []).filter(instance => supportedTypes.includes(instance.widgetType))
    readonly property real edgeInset: Theme.spacingXL * 2

    function showsOnScreen(prefs) {
        if (!Array.isArray(prefs) || prefs.length === 0 || prefs.includes("all"))
            return true;
        return prefs.some(p => {
            if (typeof p === "string")
                return p === screenKey || p === screen?.name;
            return p?.name === screen?.name || p === screenKey;
        });
    }

    function itemOfType(widgetType) {
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (item && item.visible && item.widgetType === widgetType)
                return item;
        }
        return null;
    }

    function dateForClock(item) {
        const date = itemOfType("lockDate");
        return item && item === itemOfType("desktopClock") && date && !date.hasSavedPosition ? date : null;
    }

    function dateOffset(item) {
        const date = dateForClock(item);
        return date ? date.height + Theme.spacingS : 0;
    }

    // DMS publishes the placement it resolved per screen; a screen the greeter names differently
    // falls back to another screen's placement scaled to this size.
    function publishedPosition(instanceId) {
        return positionFrom(SessionData.greeterAutoPositions, instanceId) ?? positionFrom(SessionData.lockScreenAutoPositions, instanceId);
    }

    function positionFrom(all, instanceId) {
        const exact = all[screenKey];
        if (exact?.positions?.[instanceId])
            return exact.positions[instanceId];
        for (const key in all) {
            const entry = all[key];
            const position = entry?.positions?.[instanceId];
            if (!position || !(entry.width > 0) || !(entry.height > 0))
                continue;
            return {
                x: position.x * width / entry.width,
                y: position.y * height / entry.height
            };
        }
        return null;
    }

    // Same stock layout as the DMS lock screen.
    function stockRect(widgetType, item) {
        const centerX = (width - item.width) / 2;
        const clock = itemOfType("desktopClock");
        switch (widgetType) {
        case "desktopClock":
            {
                const published = item.automaticPlacement ? publishedPosition(item.instanceId) : null;
                if (published)
                    return published;
                return {
                    x: Math.max(0, centerX),
                    y: edgeInset + dateOffset(item)
                };
            }
        case "lockDate":
            {
                const attached = item === dateForClock(clock);
                return {
                    x: attached ? (clock.x + clock.width / 2 > width / 2 ? clock.x + clock.width - item.width : clock.x) : edgeInset,
                    y: attached ? Math.max(0, clock.y - Theme.spacingS - item.height) : edgeInset
                };
            }
        case "lockAuth":
            return {
                x: centerX,
                y: height / 2 - item.height / 2
            };
        case "lockStatus":
            return {
                x: width - Theme.spacingXL - item.width,
                y: Theme.spacingXL
            };
        case "lockPower":
            return {
                x: Theme.spacingXL,
                y: height - Theme.spacingXL - item.height
            };
        case "greeterSession":
            return {
                x: width - Theme.spacingXL - item.width,
                y: height - Theme.spacingXL - item.height
            };
        }
        return null;
    }

    Repeater {
        id: repeater
        model: ScriptModel {
            objectProp: "id"
            values: root.instances
        }

        GreeterWidgetItem {
            required property var modelData
            required property int index

            instanceData: modelData
            screen: root.screen
            hostLayer: root
            lockHost: root.lockHost
            visible: modelData.enabled !== false && root.showsOnScreen(modelData.config?.displayPreferences)
            z: repeater.count - index
        }
    }
}
