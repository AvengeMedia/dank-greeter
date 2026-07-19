pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property int lowBatteryThreshold: 20

    readonly property var batteries: (UPower.devices?.values ?? []).filter(dev => dev.isLaptopBattery)
    readonly property var stateKnownBatteries: batteries.filter(b => b.ready && b.state !== UPowerDeviceState.Unknown)

    readonly property bool batteryAvailable: batteries.length > 0

    readonly property int batteryLevel: {
        if (!batteryAvailable)
            return 0;
        const valid = stateKnownBatteries.filter(b => b.percentage >= 0);
        if (valid.length === 0)
            return 0;
        const avgPercentage = valid.reduce((sum, b) => sum + b.percentage, 0) / valid.length;
        return Math.min(100, Math.round(avgPercentage * 100));
    }

    readonly property bool isCharging: stateKnownBatteries.some(b => b.state === UPowerDeviceState.Charging)
    readonly property bool isPluggedIn: !UPower.onBattery
    readonly property bool isLowBattery: batteryAvailable && batteryLevel <= lowBatteryThreshold
}
