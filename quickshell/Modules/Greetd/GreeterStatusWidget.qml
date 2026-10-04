import QtQuick
import qs.Common

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property bool background: cfg.background ?? false
    readonly property real pad: background ? Theme.spacingM : 0
    readonly property real minWidth: implicitWidth
    readonly property real minHeight: implicitHeight

    implicitWidth: statusRow.implicitWidth + pad * 2
    implicitHeight: statusRow.implicitHeight + pad * 2

    Rectangle {
        anchors.fill: parent
        visible: root.background
        radius: Theme.fullRadius(width, height)
        color: Theme.readableSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
    }

    GreeterStatusRow {
        id: statusRow
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.pad
        showWeather: root.cfg.showWeather ?? true
        useFahrenheit: SettingsData.useFahrenheit
        keyboardLayoutVisible: (root.lockHost?.keyboardLayoutCount ?? 0) > 1
        keyboardLayoutLabel: root.lockHost?.keyboardLayoutLabel ?? ""
        onKeyboardLayoutCycleRequested: root.lockHost?.cycleKeyboardLayout()
    }
}
