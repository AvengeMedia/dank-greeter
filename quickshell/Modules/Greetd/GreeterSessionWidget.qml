import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Session

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property bool resizable: false
    readonly property real minWidth: implicitWidth
    readonly property real minHeight: implicitHeight
    readonly property string currentSessionName: lockHost?.currentSessionName ?? ""
    readonly property Item authInput: lockHost?.authWidget?.inputItem ?? null
    readonly property Item placedItem: parent?.parent ?? null
    readonly property bool lowerHalf: placedItem ? placedItem.y + height / 2 > (lockHost?.height ?? 0) / 2 : true
    readonly property bool rightHalf: placedItem ? placedItem.x + width / 2 > (lockHost?.width ?? 0) / 2 : true
    readonly property real longestSessionWidth: {
        let maxWidth = 0;
        for (let i = 0; i < sessionMetrics.count; i++)
            maxWidth = Math.max(maxWidth, sessionMetrics.objectAt(i)?.width ?? 0);
        return maxWidth;
    }

    implicitWidth: Math.max(Theme.fieldDefaultWidth, currentSessionMetrics.width + Theme.buttonHeightM + Theme.spacingXL)
    implicitHeight: LockMetrics.fieldHeight

    onLockHostChanged: {
        if (lockHost)
            lockHost.sessionDropdownItem = sessionDropdown;
    }

    Component.onDestruction: {
        if (lockHost && lockHost.sessionDropdownItem === sessionDropdown)
            lockHost.sessionDropdownItem = null;
    }

    StyledTextMetrics {
        id: currentSessionMetrics
        text: root.currentSessionName
    }

    Instantiator {
        id: sessionMetrics
        model: GreeterState.sessionList
        delegate: StyledTextMetrics {
            required property string modelData
            text: modelData
        }
    }

    DDropdown {
        id: sessionDropdown
        anchors.fill: parent
        focusReturnTarget: root.authInput
        KeyNavigation.tab: root.authInput ?? sessionDropdown
        KeyNavigation.backtab: root.authInput ?? sessionDropdown
        text: ""
        description: ""
        backgroundColor: Theme.cardSurface
        hoverBackgroundColor: Theme.blend(Theme.cardSurface, Theme.onSurface, Theme.stateLayerHover)
        normalBorderColor: Theme.outlineMedium
        currentValue: root.currentSessionName
        options: GreeterState.sessionList
        enableFuzzySearch: GreeterState.sessionList.length > 5
        popupWidthOffset: 0
        popupWidth: Math.max(Theme.fieldDefaultWidth + Theme.buttonHeightM, root.longestSessionWidth + Theme.buttonHeightM + Theme.spacingXL * 2)
        openUpwards: root.lowerHalf
        alignPopupRight: root.rightHalf
        onValueChanged: value => {
            const idx = GreeterState.sessionList.indexOf(value);
            if (idx < 0)
                return;
            GreeterState.sessionManuallySelected = true;
            GreeterState.currentSessionIndex = idx;
            GreeterState.selectedSession = GreeterState.sessionExecs[idx];
            GreeterState.selectedSessionPath = GreeterState.sessionPaths[idx];
            GreeterState.selectedSessionDesktopId = GreeterState.sessionDesktopIds[idx];
            GreeterState.selectedSessionDesktopNames = GreeterState.sessionDesktopNames[idx] || "";
        }
    }
}
