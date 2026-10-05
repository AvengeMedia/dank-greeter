import QtQuick
import Quickshell
import qs.Common
import qs.DankCommon.Widgets as DankCommon

DankCommon.DankClockWidget {
    id: root

    property real widgetWidth: 280
    property real widgetHeight: 200
    property string instanceId: ""
    property var instanceData: null
    property var lockHost: null

    lockScreen: true
    cfg: instanceData?.config ?? ({})
    enabled: instanceData?.enabled ?? true
    now: systemClock.date
    locale: I18n.locale()
    use24HourClock: SettingsData.use24HourClock
    padHours12Hour: SettingsData.padHours12Hour
    dateFormat: SettingsData.lockDateFormat
    fallbackFontFamily: SettingsData.lockScreenFontFamily
    accentColor: lockHost ? lockHost.contentColor(colorMode, customColor) : themeAccent

    SystemClock {
        id: systemClock
        precision: root.needsSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }
}
