pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionData")

    readonly property bool isGreeterMode: Quickshell.env("DMS_RUN_GREETER") === "1" || Quickshell.env("DMS_RUN_GREETER") === "true"

    property bool isLightMode: false
    property string wallpaperPath: ""
    property bool perMonitorWallpaper: false
    property var monitorWallpapers: ({})
    property string weatherLocation: "New York, NY"
    property string weatherCoordinates: "40.7128,-74.0060"

    function parseSettings(content) {
        try {
            let s = {};
            if (content && content.trim())
                s = JSON.parse(content);

            isLightMode = s.isLightMode !== undefined ? s.isLightMode : false;
            wallpaperPath = s.wallpaperPath !== undefined ? s.wallpaperPath : "";
            perMonitorWallpaper = s.perMonitorWallpaper !== undefined ? s.perMonitorWallpaper : false;
            monitorWallpapers = s.monitorWallpapers !== undefined ? s.monitorWallpapers : ({});
            weatherLocation = s.weatherLocation !== undefined ? s.weatherLocation : "New York, NY";
            weatherCoordinates = s.weatherCoordinates !== undefined ? s.weatherCoordinates : "40.7128,-74.0060";
        } catch (e) {
            log.warn("Failed to parse greeter session.json:", e);
        }
    }

    // DMS may key monitor wallpapers by screen name, model, or "model-N" display name
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
