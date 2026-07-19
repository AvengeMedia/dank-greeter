pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("SettingsData")

    enum AnimationSpeed {
        None,
        Short,
        Medium,
        Long,
        Custom
    }

    enum TextRenderType {
        Qt,
        Native,
        Curve
    }

    enum TextRenderQuality {
        Default,
        Low,
        Normal,
        High,
        VeryHigh
    }

    readonly property string _greeterCacheDir: Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter"

    property bool settingsLoaded: false

    property int animationSpeed: SettingsData.AnimationSpeed.Short
    property int customAnimationDuration: 500
    property bool enableRippleEffects: true
    property bool popoutElevationEnabled: true
    property int textRenderType: SettingsData.TextRenderType.Qt
    property int textRenderQuality: SettingsData.TextRenderQuality.Default

    property string clockFormat: "auto"
    readonly property bool localeUses24Hour: {
        const fmt = Qt.locale().timeFormat(Locale.ShortFormat).replace(/'[^']*'/g, "");
        return !/[aA]/.test(fmt);
    }
    readonly property bool use24HourClock: clockFormat === "24h" ? true : (clockFormat === "12h" ? false : localeUses24Hour)

    property bool useFahrenheit: false
    property string windSpeedUnit: "kmh"
    property bool useAutoLocation: false
    property bool weatherEnabled: true
    readonly property string weatherLocation: SessionData.weatherLocation
    readonly property string weatherCoordinates: SessionData.weatherCoordinates

    property string fontFamily: "Inter Variable"
    property string monoFontFamily: "Fira Code"
    property int fontWeight: Font.Normal
    property real fontScale: 1.0
    property real cornerRadius: 12

    property bool powerActionConfirm: true
    property real powerActionHoldDuration: 0.5
    property var powerMenuActions: ["reboot", "logout", "poweroff", "lock", "suspend", "restart"]
    property string powerMenuDefaultAction: "logout"
    property bool powerMenuGridLayout: false

    function parseSettings(content) {
        try {
            let s = {};
            if (content && content.trim())
                s = JSON.parse(content);

            animationSpeed = s.animationSpeed !== undefined ? s.animationSpeed : SettingsData.AnimationSpeed.Short;
            customAnimationDuration = s.customAnimationDuration !== undefined ? s.customAnimationDuration : 500;
            enableRippleEffects = s.enableRippleEffects !== undefined ? s.enableRippleEffects : true;
            popoutElevationEnabled = s.popoutElevationEnabled !== undefined ? s.popoutElevationEnabled : true;
            textRenderType = s.textRenderType !== undefined ? s.textRenderType : SettingsData.TextRenderType.Qt;
            textRenderQuality = s.textRenderQuality !== undefined ? s.textRenderQuality : SettingsData.TextRenderQuality.Default;
            clockFormat = s.clockFormat !== undefined ? s.clockFormat : (s.use24HourClock !== undefined ? (s.use24HourClock ? "24h" : "12h") : "auto");
            useFahrenheit = s.useFahrenheit !== undefined ? s.useFahrenheit : false;
            windSpeedUnit = s.windSpeedUnit !== undefined ? s.windSpeedUnit : "kmh";
            useAutoLocation = s.useAutoLocation !== undefined ? s.useAutoLocation : false;
            weatherEnabled = s.weatherEnabled !== undefined ? s.weatherEnabled : true;
            fontFamily = s.fontFamily !== undefined ? s.fontFamily : "Inter Variable";
            monoFontFamily = s.monoFontFamily !== undefined ? s.monoFontFamily : "Fira Code";
            fontWeight = s.fontWeight !== undefined ? s.fontWeight : Font.Normal;
            fontScale = s.fontScale !== undefined ? s.fontScale : 1.0;
            cornerRadius = s.cornerRadius !== undefined ? s.cornerRadius : 12;
            powerActionConfirm = s.powerActionConfirm !== undefined ? s.powerActionConfirm : true;
            powerActionHoldDuration = s.powerActionHoldDuration !== undefined ? s.powerActionHoldDuration : 0.5;
            powerMenuActions = s.powerMenuActions !== undefined ? s.powerMenuActions : ["reboot", "logout", "poweroff", "lock", "suspend", "restart"];
            powerMenuDefaultAction = s.powerMenuDefaultAction !== undefined ? s.powerMenuDefaultAction : "logout";
            powerMenuGridLayout = s.powerMenuGridLayout !== undefined ? s.powerMenuGridLayout : false;
        } catch (e) {
            log.warn("Failed to parse greeter settings.json:", e);
        } finally {
            settingsLoaded = true;
        }
    }

    FileView {
        id: settingsFile
        path: root._greeterCacheDir + "/settings.json"
        blockLoading: false
        blockWrites: true
        watchChanges: false
        printErrors: false

        onLoaded: {
            root.parseSettings(settingsFile.text());
        }

        onLoadFailed: {
            root.parseSettings("");
        }
    }
}
