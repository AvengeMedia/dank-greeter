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

    property int animationSpeed: SettingsData.AnimationSpeed.Short
    property int customAnimationDuration: 500
    property bool enableRippleEffects: true
    property bool popoutElevationEnabled: true
    property int textRenderType: SettingsData.TextRenderType.Qt
    property int textRenderQuality: SettingsData.TextRenderQuality.Default

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
            powerActionConfirm = s.powerActionConfirm !== undefined ? s.powerActionConfirm : true;
            powerActionHoldDuration = s.powerActionHoldDuration !== undefined ? s.powerActionHoldDuration : 0.5;
            powerMenuActions = s.powerMenuActions !== undefined ? s.powerMenuActions : ["reboot", "logout", "poweroff", "lock", "suspend", "restart"];
            powerMenuDefaultAction = s.powerMenuDefaultAction !== undefined ? s.powerMenuDefaultAction : "logout";
            powerMenuGridLayout = s.powerMenuGridLayout !== undefined ? s.powerMenuGridLayout : false;
        } catch (e) {
            log.warn("Failed to parse greeter settings.json:", e);
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
