import QtQuick
import qs.Common

QtObject {
    id: root

    property string instanceId: ""
    property var instanceData: null
    property var screen: null
    property real minWidth: 100
    property real minHeight: 100
    property bool forceSquare: false
    property real defaultWidth: 280
    property real defaultHeight: 180
    property real defaultX: screenWidth / 2 - savedWidth / 2
    property real defaultY: screenHeight / 2 - savedHeight / 2

    readonly property bool syncPositionAcrossScreens: instanceData?.config?.syncPositionAcrossScreens ?? false
    readonly property string screenKey: SettingsData.getScreenDisplayName(screen)
    readonly property string positionKey: syncPositionAcrossScreens ? "_synced" : screenKey
    readonly property var storedPositions: SessionData.desktopWidgetInstancePositions[instanceId] ?? null
    readonly property var anchorKeys: ({
            x: "anchorX",
            y: "anchorY"
        })
    readonly property int screenWidth: screen?.width ?? 1920
    readonly property int screenHeight: screen?.height ?? 1080

    function storedGeometry(key) {
        return storedPositions?.[positionKey]?.[key];
    }

    function anchoredPosition(anchor, offset, extent, size) {
        switch (anchor) {
        case "center":
            return (extent - size) / 2 + offset;
        case "end":
            return extent - size - offset;
        }
        return offset;
    }

    function storedCoordinate(key, extent, size, fallback) {
        const offset = storedGeometry(key);
        if (offset === undefined)
            return fallback;
        return anchoredPosition(storedGeometry(anchorKeys[key]), syncPositionAcrossScreens ? offset * extent : offset, extent, size);
    }

    readonly property bool hasSavedPosition: storedGeometry("x") !== undefined
    readonly property real savedWidth: storedGeometry("width") ?? defaultWidth
    readonly property real savedHeight: forceSquare ? savedWidth : (storedGeometry("height") ?? defaultHeight)
    readonly property real savedX: storedCoordinate("x", screenWidth, widgetWidth, defaultX)
    readonly property real savedY: storedCoordinate("y", screenHeight, widgetHeight, defaultY)

    readonly property real widgetWidth: Math.max(minWidth, Math.min(savedWidth, screenWidth))
    readonly property real widgetHeight: Math.max(minHeight, Math.min(savedHeight, screenHeight))
    readonly property real widgetX: Math.max(0, Math.min(savedX, screenWidth - widgetWidth))
    readonly property real widgetY: Math.max(0, Math.min(savedY, screenHeight - widgetHeight))
}
