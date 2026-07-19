pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: root

    readonly property var allDevices: Networking.devices?.values ?? []
    readonly property var wiredDevice: allDevices.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var wifiDevice: allDevices.find(d => d.type === DeviceType.Wifi) ?? null

    readonly property bool ethernetConnected: wiredDevice?.connected ?? false
    readonly property bool wifiConnected: wifiDevice?.connected ?? false

    readonly property var connectedWifiNetwork: {
        const list = wifiDevice?.networks?.values ?? [];
        return list.find(net => net.connected) ?? null;
    }

    readonly property string currentWifiSSID: connectedWifiNetwork?.name ?? ""
    readonly property int wifiSignalStrength: Math.round((connectedWifiNetwork?.signalStrength ?? 0) * 100)

    readonly property string networkStatus: {
        if (ethernetConnected)
            return "ethernet";
        if (wifiConnected)
            return "wifi";
        return "disconnected";
    }

    readonly property string wifiSignalIcon: {
        if (!wifiConnected || networkStatus !== "wifi")
            return "wifi_off";
        if (wifiSignalStrength >= 50)
            return "wifi";
        if (wifiSignalStrength >= 25)
            return "wifi_2_bar";
        return "wifi_1_bar";
    }
}
