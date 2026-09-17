pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "../DankCommon/Common/settings/SharedSessionSpec.js" as Spec
import "../DankCommon/Common/settings/SpecUtil.js" as SpecUtil

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionData")

    property bool isLightMode: Spec.SPEC.isLightMode.def
    property string wallpaperPath: Spec.SPEC.wallpaperPath.def
    property bool perMonitorWallpaper: Spec.SPEC.perMonitorWallpaper.def
    property var monitorWallpapers: Spec.SPEC.monitorWallpapers.def
    property var monitorWallpaperFillModes: Spec.SPEC.monitorWallpaperFillModes.def
    property string weatherLocation: Spec.SPEC.weatherLocation.def
    property string weatherCoordinates: Spec.SPEC.weatherCoordinates.def

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
