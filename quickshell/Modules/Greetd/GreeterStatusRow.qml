import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Row {
    id: root

    property bool showWeather: true
    property bool useFahrenheit: false
    property bool keyboardLayoutVisible: false
    property string keyboardLayoutLabel: ""

    signal keyboardLayoutCycleRequested

    readonly property color contentColor: Theme.lockScreenContentColor
    readonly property color dimColor: Theme.withAlpha(contentColor, Theme.pendingOpacity)
    readonly property color dividerColor: Theme.withAlpha(contentColor, Theme.stateLayerPressed)
    readonly property bool weatherVisible: showWeather && WeatherService.weather.available
    readonly property bool afterWeather: systemRow.visible || batteryRow.visible
    readonly property bool afterKeyboard: weatherVisible || afterWeather
    readonly property color batteryColor: {
        if (BatteryService.isLowBattery && !BatteryService.isCharging)
            return Theme.error;
        if (BatteryService.isCharging || BatteryService.isPluggedIn)
            return Theme.primary;
        return contentColor;
    }

    spacing: Theme.spacingL

    component Divider: Rectangle {
        width: Theme.dividerWidth
        height: Theme.iconSize
        color: root.dividerColor
        anchors.verticalCenter: parent.verticalCenter
    }

    Item {
        id: keyboardLayout
        width: keyboardLayoutRow.width
        height: keyboardLayoutRow.height
        anchors.verticalCenter: parent.verticalCenter
        visible: root.keyboardLayoutVisible

        Row {
            id: keyboardLayoutRow
            spacing: Theme.spacingXS

            DankIcon {
                name: "keyboard"
                size: Theme.iconSize
                color: root.contentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.keyboardLayoutLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeight
                color: root.contentColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.keyboardLayoutCycleRequested()
        }
    }

    Divider {
        visible: keyboardLayout.visible && root.afterKeyboard
    }

    Row {
        id: weatherRow
        spacing: Theme.spacingXS
        visible: root.weatherVisible
        anchors.verticalCenter: parent.verticalCenter

        DankIcon {
            name: WeatherService.getWeatherIcon(WeatherService.weather.wCode)
            size: Theme.iconSize
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: (root.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp) + "°"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeight
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Divider {
        visible: weatherRow.visible && root.afterWeather
    }

    Row {
        id: systemRow
        spacing: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        visible: NetworkService.networkStatus !== "disconnected" || (BluetoothService.available && BluetoothService.enabled) || (AudioService.sink && AudioService.sink.audio)

        DankIcon {
            name: NetworkService.networkStatus === "ethernet" ? "lan" : NetworkService.wifiSignalIcon
            size: Theme.iconSizeSmall
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
            visible: NetworkService.networkStatus !== "disconnected"
        }

        DankIcon {
            name: "bluetooth"
            size: Theme.iconSizeSmall
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
            visible: BluetoothService.available && BluetoothService.enabled
        }

        DankIcon {
            name: AudioService.sinkVolumeIconName
            size: Theme.iconSizeSmall
            color: AudioService.sinkSilent ? root.dimColor : root.contentColor
            anchors.verticalCenter: parent.verticalCenter
            visible: AudioService.sink && AudioService.sink.audio
        }
    }

    Divider {
        visible: systemRow.visible && batteryRow.visible
    }

    Row {
        id: batteryRow
        spacing: Theme.spacingXS
        visible: BatteryService.batteryAvailable
        anchors.verticalCenter: parent.verticalCenter

        DankIcon {
            name: BatteryService.getBatteryIcon()
            size: Theme.iconSize
            color: root.batteryColor
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: BatteryService.batteryLevel + "%"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeight
            color: root.contentColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
