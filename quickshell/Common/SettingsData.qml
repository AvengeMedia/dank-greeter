pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "../DankCommon/Common/Shape.js" as Shape
import "../DankCommon/Common/settings/SharedSettingsSpec.js" as Spec
import "../DankCommon/Common/settings/SpecUtil.js" as SpecUtil

Singleton {
    id: root
    readonly property var log: Log.scoped("SettingsData")

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

    property string configBaseDir: root._greeterCacheDir
    readonly property string configPath: configBaseDir ? (configBaseDir + "/settings.json") : ""
    property bool loaded: false

    function setConfigBaseDir(dir) {
        const next = dir || root._greeterCacheDir;
        if (configBaseDir === next)
            return;
        configBaseDir = next;
        loaded = false;
        settingsFile.reload();
    }

    function resetConfigBaseDir() {
        setConfigBaseDir(root._greeterCacheDir);
    }

    property string currentThemeName: Spec.SPEC.currentThemeName.def
    property string customThemeFile: Spec.SPEC.customThemeFile.def
    property var registryThemeVariants: Spec.SPEC.registryThemeVariants.def

    property string clockFormat: Spec.SPEC.clockFormat.def
    property bool showSeconds: Spec.SPEC.showSeconds.def
    property bool padHours12Hour: Spec.SPEC.padHours12Hour.def
    property bool useFahrenheit: Spec.SPEC.useFahrenheit.def
    property bool useAutoLocation: Spec.SPEC.useAutoLocation.def
    property bool weatherEnabled: Spec.SPEC.weatherEnabled.def

    property string fontFamily: Spec.SPEC.fontFamily.def
    property string monoFontFamily: Spec.SPEC.monoFontFamily.def
    property int fontWeight: Spec.SPEC.fontWeight.def
    property real fontScale: Spec.SPEC.fontScale.def
    property real radiusStrength: Spec.SPEC.radiusStrength.def
    property int animationDuration: Spec.SPEC.animationDuration.def
    property bool enableRippleEffects: Spec.SPEC.enableRippleEffects.def
    property bool popoutElevationEnabled: Spec.SPEC.popoutElevationEnabled.def
    property int textRenderType: Spec.SPEC.textRenderType.def
    property int textRenderQuality: Spec.SPEC.textRenderQuality.def
    property bool blurBorderEnabled: Spec.SPEC.blurBorderEnabled.def
    property string blurBorderColor: Spec.SPEC.blurBorderColor.def
    property string blurBorderCustomColor: Spec.SPEC.blurBorderCustomColor.def
    property real blurBorderOpacity: Spec.SPEC.blurBorderOpacity.def

    property string lockDateFormat: Spec.SPEC.lockDateFormat.def
    property bool lockScreenShowPowerActions: Spec.SPEC.lockScreenShowPowerActions.def
    property bool lockScreenShowProfileImage: Spec.SPEC.lockScreenShowProfileImage.def
    property bool lockScreenShowWeather: Spec.SPEC.lockScreenShowWeather.def
    property string lockScreenWallpaperPath: Spec.SPEC.lockScreenWallpaperPath.def
    property string lockScreenWallpaperFillMode: Spec.SPEC.lockScreenWallpaperFillMode.def
    property string lockScreenFontFamily: Spec.SPEC.lockScreenFontFamily.def

    property bool greeterRememberLastSession: Spec.SPEC.greeterRememberLastSession.def
    property bool greeterRememberLastUser: Spec.SPEC.greeterRememberLastUser.def
    property bool greeterEnableFprint: Spec.SPEC.greeterEnableFprint.def
    property bool greeterEnableU2f: Spec.SPEC.greeterEnableU2f.def

    property bool powerActionConfirm: Spec.SPEC.powerActionConfirm.def
    property real powerActionHoldDuration: Spec.SPEC.powerActionHoldDuration.def
    property var powerMenuActions: Spec.SPEC.powerMenuActions.def
    property string powerMenuDefaultAction: Spec.SPEC.powerMenuDefaultAction.def
    property bool powerMenuGridLayout: Spec.SPEC.powerMenuGridLayout.def

    property string wallpaperFillMode: Spec.SPEC.wallpaperFillMode.def
    property string wallpaperBackgroundColorMode: Spec.SPEC.wallpaperBackgroundColorMode.def
    property string wallpaperBackgroundCustomColor: Spec.SPEC.wallpaperBackgroundCustomColor.def

    readonly property bool localeUses24Hour: {
        const fmt = Qt.locale().timeFormat(Locale.ShortFormat).replace(/'[^']*'/g, "");
        return !/[aA]/.test(fmt);
    }
    readonly property bool use24HourClock: clockFormat === "24h" ? true : (clockFormat === "12h" ? false : localeUses24Hour)

    readonly property color effectiveWallpaperBackgroundColor: {
        switch (wallpaperBackgroundColorMode) {
        case "black":
            return "#000000";
        case "white":
            return "#ffffff";
        case "primary":
            return (typeof Theme !== "undefined") ? Theme.primary : "#000000";
        case "surface":
            return (typeof Theme !== "undefined") ? Theme.surfaceContainer : "#000000";
        case "custom":
            return wallpaperBackgroundCustomColor;
        default:
            return "#000000";
        }
    }

    function getEffectiveTimeFormat() {
        if (use24HourClock)
            return showSeconds ? "hh:mm:ss" : "hh:mm";
        if (padHours12Hour)
            return showSeconds ? "hh:mm:ss AP" : "hh:mm AP";
        return showSeconds ? "h:mm:ss AP" : "h:mm AP";
    }

    function readSettings(content) {
        if (!content || !content.trim())
            return {};
        try {
            return JSON.parse(content);
        } catch (e) {
            log.warn("Failed to parse greeter settings.json:", e);
            return {};
        }
    }

    function parseSettings(content) {
        const settings = readSettings(content);
        if (settings.radiusStrength === undefined && settings.cornerRadius !== undefined)
            settings.radiusStrength = Shape.strengthFromRadius(settings.cornerRadius * Shape.corners.m / Shape.corners.l);
        for (const key in Spec.SPEC) {
            if (!root.hasOwnProperty(key))
                continue;
            const spec = Spec.SPEC[key];
            if (!(key in settings)) {
                root[key] = SpecUtil.cloneDef(spec.def);
                continue;
            }
            const value = spec.coerce ? spec.coerce(settings[key]) : settings[key];
            root[key] = value !== undefined ? value : SpecUtil.cloneDef(spec.def);
        }
        if (typeof Theme !== "undefined")
            Theme.applyGreeterTheme(currentThemeName);
        loaded = true;
    }

    FileView {
        id: settingsFile
        path: root.configPath
        blockLoading: false
        blockWrites: true
        atomicWrites: false
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
