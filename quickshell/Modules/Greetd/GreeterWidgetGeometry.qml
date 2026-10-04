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
    readonly property int screenWidth: screen?.width ?? 1920
    readonly property int screenHeight: screen?.height ?? 1080

    function storedGeometry(key) {
        return storedPositions?.[positionKey]?.[key];
    }

    function storedCoordinate(key, extent, fallback) {
        const val = storedGeometry(key);
        if (val === undefined)
            return fallback;
        return syncPositionAcrossScreens ? val * extent : val;
    }

    readonly property bool hasSavedPosition: storedGeometry("x") !== undefined
    readonly property real savedWidth: storedGeometry("width") ?? defaultWidth
    readonly property real savedHeight: forceSquare ? savedWidth : (storedGeometry("height") ?? defaultHeight)
    readonly property real savedX: storedCoordinate("x", screenWidth, defaultX)
    readonly property real savedY: storedCoordinate("y", screenHeight, defaultY)

    readonly property real widgetWidth: Math.max(minWidth, Math.min(savedWidth, screenWidth))
    readonly property real widgetHeight: Math.max(minHeight, Math.min(savedHeight, screenHeight))
    readonly property real widgetX: Math.max(0, Math.min(savedX, screenWidth - widgetWidth))
    readonly property real widgetY: Math.max(0, Math.min(savedY, screenHeight - widgetHeight))
}
