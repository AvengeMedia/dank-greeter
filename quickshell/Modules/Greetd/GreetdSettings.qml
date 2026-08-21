pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "GreetdEnv.js" as GreetdEnv

Singleton {
    id: root
    readonly property var log: Log.scoped("GreetdSettings")

    readonly property string _greeterCacheDir: Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter"

    property string configBaseDir: root._greeterCacheDir
    property string configHomeDir: ""
    readonly property string configPath: root.configBaseDir ? (root.configBaseDir + "/settings.json") : ""
    readonly property string greeterWallpaperOverridePath: root.configBaseDir ? (root.configBaseDir + "/greeter_wallpaper_override.jpg") : ""

    function setConfigBaseDir(dir, homeDir) {
        const next = dir || root._greeterCacheDir;
        const nextHome = homeDir || "";
        if (configBaseDir === next && configHomeDir === nextHome)
            return;
        configBaseDir = next;
        configHomeDir = nextHome;
        settingsLoaded = false;
        settingsFile.reload();
    }

    function resetConfigBaseDir() {
        setConfigBaseDir(root._greeterCacheDir, "");
    }

    function resolveUserPath(path) {
        if (!path || !configHomeDir)
            return Paths.expandTilde(path || "");
        if (path === "~")
            return configHomeDir;
        if (path.startsWith("~/"))
            return configHomeDir + path.substring(1);
        if (path.startsWith("/"))
            return path;
        return configHomeDir + "/" + path;
    }

    property string currentThemeName: "purple"
    property bool settingsLoaded: false
    property string customThemeFile: ""
    property var registryThemeVariants: ({})
    property string clockFormat: "auto"
    readonly property bool localeUses24Hour: {
        const fmt = Qt.locale().timeFormat(Locale.ShortFormat).replace(/'[^']*'/g, "");
        return !/[aA]/.test(fmt);
    }
    readonly property bool use24HourClock: clockFormat === "24h" ? true : (clockFormat === "12h" ? false : localeUses24Hour)
    property bool showSeconds: false
    property bool padHours12Hour: false
    property string greeterLockDateFormat: ""
    property string greeterFontFamily: ""
    property string greeterWallpaperFillMode: ""
    property bool useFahrenheit: false
    property bool useAutoLocation: false
    property bool weatherEnabled: true
    property string fontFamily: "Inter Variable"
    property string monoFontFamily: "Fira Code"
    property int fontWeight: Font.Normal
    property real fontScale: 1.0
    property real cornerRadius: 12
    property string lockDateFormat: ""
    property bool lockScreenShowPowerActions: true
    property bool lockScreenShowProfileImage: true
    property bool rememberLastSession: true
    property bool rememberLastUser: true
    property bool greeterEnableFprint: false
    property bool greeterEnableU2f: false
    property string greeterWallpaperPath: ""
    property bool powerActionConfirm: true
    property real powerActionHoldDuration: 0.5
    property var powerMenuActions: ["reboot", "logout", "poweroff", "lock", "suspend", "restart"]
    property string powerMenuDefaultAction: "logout"
    property bool powerMenuGridLayout: false
    property string wallpaperFillMode: "Fill"
    property string wallpaperBackgroundColorMode: "black"
    property string wallpaperBackgroundCustomColor: "#000000"
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

    function parseSettings(content) {
        try {
            let settings = {};
            if (content && content.trim()) {
                settings = JSON.parse(content);
            }

            const envRememberLastSession = GreetdEnv.readBoolOverride(Quickshell.env, ["DMS_GREET_REMEMBER_LAST_SESSION", "DMS_SAVE_SESSION"], undefined, log);
            const envRememberLastUser = GreetdEnv.readBoolOverride(Quickshell.env, ["DMS_GREET_REMEMBER_LAST_USER", "DMS_SAVE_USERNAME"], undefined, log);

            currentThemeName = settings.currentThemeName !== undefined ? settings.currentThemeName : "purple";
            customThemeFile = settings.customThemeFile !== undefined ? settings.customThemeFile : "";
            registryThemeVariants = settings.registryThemeVariants !== undefined ? settings.registryThemeVariants : ({});
            clockFormat = settings.clockFormat !== undefined ? settings.clockFormat : (settings.use24HourClock !== undefined ? (settings.use24HourClock ? "24h" : "12h") : "auto");
            showSeconds = settings.showSeconds !== undefined ? settings.showSeconds : false;
            padHours12Hour = settings.padHours12Hour !== undefined ? settings.padHours12Hour : false;
            greeterLockDateFormat = settings.greeterLockDateFormat !== undefined ? settings.greeterLockDateFormat : "";
            greeterFontFamily = settings.greeterFontFamily !== undefined ? settings.greeterFontFamily : "";
            greeterWallpaperFillMode = settings.greeterWallpaperFillMode !== undefined ? settings.greeterWallpaperFillMode : "";
            useFahrenheit = settings.useFahrenheit !== undefined ? settings.useFahrenheit : false;
            useAutoLocation = settings.useAutoLocation !== undefined ? settings.useAutoLocation : false;
            weatherEnabled = settings.weatherEnabled !== undefined ? settings.weatherEnabled : true;
            fontFamily = settings.fontFamily !== undefined ? settings.fontFamily : Theme.defaultFontFamily;
            monoFontFamily = settings.monoFontFamily !== undefined ? settings.monoFontFamily : Theme.defaultMonoFontFamily;
            fontWeight = settings.fontWeight !== undefined ? settings.fontWeight : Font.Normal;
            fontScale = settings.fontScale !== undefined ? settings.fontScale : 1.0;
            cornerRadius = settings.cornerRadius !== undefined ? settings.cornerRadius : 12;
            lockDateFormat = settings.lockDateFormat !== undefined ? settings.lockDateFormat : "";
            lockScreenShowPowerActions = settings.lockScreenShowPowerActions !== undefined ? settings.lockScreenShowPowerActions : true;
            lockScreenShowProfileImage = settings.lockScreenShowProfileImage !== undefined ? settings.lockScreenShowProfileImage : true;
            if (envRememberLastSession !== undefined) {
                rememberLastSession = envRememberLastSession;
            } else {
                rememberLastSession = settings.greeterRememberLastSession !== undefined ? settings.greeterRememberLastSession : settings.rememberLastSession !== undefined ? settings.rememberLastSession : true;
            }
            if (envRememberLastUser !== undefined) {
                rememberLastUser = envRememberLastUser;
            } else {
                rememberLastUser = settings.greeterRememberLastUser !== undefined ? settings.greeterRememberLastUser : settings.rememberLastUser !== undefined ? settings.rememberLastUser : true;
            }
            greeterEnableFprint = settings.greeterEnableFprint !== undefined ? settings.greeterEnableFprint : false;
            greeterEnableU2f = settings.greeterEnableU2f !== undefined ? settings.greeterEnableU2f : false;
            greeterWallpaperPath = settings.greeterWallpaperPath !== undefined ? settings.greeterWallpaperPath : "";
            powerActionConfirm = settings.powerActionConfirm !== undefined ? settings.powerActionConfirm : true;
            powerActionHoldDuration = settings.powerActionHoldDuration !== undefined ? settings.powerActionHoldDuration : 0.5;
            powerMenuActions = settings.powerMenuActions !== undefined ? settings.powerMenuActions : ["reboot", "logout", "poweroff", "lock", "suspend", "restart"];
            powerMenuDefaultAction = settings.powerMenuDefaultAction !== undefined ? settings.powerMenuDefaultAction : "logout";
            powerMenuGridLayout = settings.powerMenuGridLayout !== undefined ? settings.powerMenuGridLayout : false;
            wallpaperFillMode = settings.wallpaperFillMode !== undefined ? settings.wallpaperFillMode : "Fill";
            wallpaperBackgroundColorMode = settings.wallpaperBackgroundColorMode !== undefined ? settings.wallpaperBackgroundColorMode : "black";
            wallpaperBackgroundCustomColor = settings.wallpaperBackgroundCustomColor !== undefined ? settings.wallpaperBackgroundCustomColor : "#000000";

            if (typeof Theme !== "undefined") {
                if (currentThemeName === "custom" && customThemeFile) {
                    Theme.loadCustomThemeFromFile(resolveUserPath(customThemeFile));
                }
                Theme.applyGreeterTheme(currentThemeName);
            }
        } catch (e) {
            log.warn("Failed to parse greetd settings:", e);
        } finally {
            settingsLoaded = true;
        }
    }

    function getEffectiveTimeFormat() {
        const use24 = use24HourClock;
        const secs = showSeconds;
        const pad = padHours12Hour;
        if (use24)
            return secs ? "hh:mm:ss" : "hh:mm";
        if (pad)
            return secs ? "hh:mm:ss AP" : "hh:mm AP";
        return secs ? "h:mm:ss AP" : "h:mm AP";
    }

    function getEffectiveLockDateFormat() {
        const fmt = (greeterLockDateFormat !== undefined && greeterLockDateFormat !== "") ? greeterLockDateFormat : lockDateFormat;
        return fmt && fmt.length > 0 ? fmt : Locale.LongFormat;
    }

    function getEffectiveWallpaperFillMode() {
        return (greeterWallpaperFillMode && greeterWallpaperFillMode !== "") ? greeterWallpaperFillMode : wallpaperFillMode;
    }

    function getEffectiveFontFamily() {
        return (greeterFontFamily && greeterFontFamily !== "") ? greeterFontFamily : fontFamily;
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
            parseSettings(settingsFile.text());
        }
        onLoadFailed: {
            root.parseSettings("");
        }
    }
}
