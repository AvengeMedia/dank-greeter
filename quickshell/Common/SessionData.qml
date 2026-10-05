pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "../DCommon/Common/MaterialWallpaper.js" as MaterialWallpaper
import "../DCommon/Common/settings/SharedSessionSpec.js" as Spec
import "../DCommon/Common/settings/SpecUtil.js" as SpecUtil

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionData")

    property bool isLightMode: Spec.SPEC.isLightMode.def
    property string wallpaperPath: Spec.SPEC.wallpaperPath.def
    property bool perMonitorWallpaper: Spec.SPEC.perMonitorWallpaper.def
    property bool perModeWallpaper: Spec.SPEC.perModeWallpaper.def
    property var materialWallpapers: Spec.SPEC.materialWallpapers.def
    property var monitorWallpapers: Spec.SPEC.monitorWallpapers.def
    property var monitorWallpaperFillModes: Spec.SPEC.monitorWallpaperFillModes.def
    property string weatherLocation: Spec.SPEC.weatherLocation.def
    property string weatherCoordinates: Spec.SPEC.weatherCoordinates.def
    property var desktopWidgetInstancePositions: Spec.SPEC.desktopWidgetInstancePositions.def
    property var lockScreenAutoPositions: Spec.SPEC.lockScreenAutoPositions.def
    property var greeterAutoPositions: Spec.SPEC.greeterAutoPositions.def

    function readSession(content) {
        if (!content || !content.trim())
            return {};
        try {
            return JSON.parse(content);
        } catch (e) {
            log.warn("Failed to parse greeter session.json:", e);
            return {};
        }
    }

    function parseSettings(content) {
        const session = readSession(content);
        for (const key in Spec.SPEC) {
            if (!root.hasOwnProperty(key))
                continue;
            const spec = Spec.SPEC[key];
            if (!(key in session)) {
                root[key] = SpecUtil.cloneDef(spec.def);
                continue;
            }
            const value = spec.coerce ? spec.coerce(session[key]) : session[key];
            root[key] = value !== undefined ? value : SpecUtil.cloneDef(spec.def);
        }
    }

    function _findMonitorValue(map, screenName) {
        if (!map)
            return undefined;

        let screen = null;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen)
            return map[screenName];

        if (map[screen.name] !== undefined)
            return map[screen.name];
        if (!screen.model)
            return undefined;
        if (map[screen.model] !== undefined)
            return map[screen.model];
        for (const key in map) {
            if (key.indexOf(screen.model + "-") === 0)
                return map[key];
        }
        return undefined;
    }

    function _screenByName(screenName) {
        return Array.from(Quickshell.screens).find(screen => screen.name === screenName) ?? null;
    }

    function materialWallpaperTarget(screenName) {
        const screen = perMonitorWallpaper ? _screenByName(screenName) : null;
        return {
            screen: perMonitorWallpaper ? screenName : "",
            key: screen ? SettingsData.getScreenDisplayName(screen) : "",
            separate: perModeWallpaper,
            light: isLightMode,
            perMonitor: perMonitorWallpaper
        };
    }

    function materialWallpaperEntry(target) {
        const slot = target.separate ? (target.light ? "light" : "dark") : "shared";
        const inherits = !target.perMonitor || _findMonitorValue(monitorWallpapers, target.screen) === undefined;
        const slots = inherits ? materialWallpapers[""] : _findMonitorValue(materialWallpapers, target.screen);
        const key = inherits ? "" : target.key;
        return MaterialWallpaper.entry({
            "": materialWallpapers[""],
            [key]: slots
        }, key, slot);
    }

    function getMonitorMaterialWallpaper(screenName) {
        return MaterialWallpaper.composition(materialWallpaperEntry(materialWallpaperTarget(screenName)));
    }

    function getMonitorWallpaper(screenName) {
        if (!perMonitorWallpaper)
            return wallpaperPath;
        const value = _findMonitorValue(monitorWallpapers, screenName);
        return value !== undefined ? value : wallpaperPath;
    }

    function getMonitorWallpaperFillMode(screenName) {
        const globalFillMode = (typeof SettingsData !== "undefined") ? SettingsData.wallpaperFillMode : "Fill";
        if (!perMonitorWallpaper)
            return globalFillMode;
        const value = _findMonitorValue(monitorWallpaperFillModes, screenName);
        return value !== undefined ? value : globalFillMode;
    }

    readonly property string _greeterCacheDir: Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter"

    property string greeterSessionBaseDir: root._greeterCacheDir

    function setGreeterSessionBaseDir(dir) {
        const next = dir || root._greeterCacheDir;
        if (greeterSessionBaseDir === next)
            return;
        greeterSessionBaseDir = next;
        greeterSessionFile.reload();
    }

    function resetGreeterSessionBaseDir() {
        setGreeterSessionBaseDir(root._greeterCacheDir);
    }

    FileView {
        id: greeterSessionFile
        path: root.greeterSessionBaseDir ? (root.greeterSessionBaseDir + "/session.json") : ""
        blockLoading: false
        blockWrites: true
        watchChanges: false
        printErrors: false

        onLoaded: {
            root.parseSettings(greeterSessionFile.text());
        }

        onLoadFailed: {
            root.parseSettings("");
        }
    }
}
