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

    function getBatteryIcon() {
        if (!batteryAvailable)
            return "power";
        if (isCharging || isPluggedIn)
            return chargingIcon(batteryLevel);
        return dischargingIcon(batteryLevel);
    }

    function chargingIcon(level) {
        if (level >= 90)
            return "battery_charging_full";
        if (level >= 80)
            return "battery_charging_90";
        if (level >= 60)
            return "battery_charging_80";
        if (level >= 50)
            return "battery_charging_60";
        if (level >= 30)
            return "battery_charging_50";
        if (level >= 20)
            return "battery_charging_30";
        return "battery_charging_20";
    }

    function dischargingIcon(level) {
        if (level >= 95)
            return "battery_full";
        if (level >= 85)
            return "battery_6_bar";
        if (level >= 70)
            return "battery_5_bar";
        if (level >= 55)
            return "battery_4_bar";
        if (level >= 40)
            return "battery_3_bar";
        if (level >= 25)
            return "battery_2_bar";
        return "battery_1_bar";
    }
}
