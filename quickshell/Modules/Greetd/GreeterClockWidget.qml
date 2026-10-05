import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import "../../DankCommon/Common/Hct.js" as Hct

Item {
    id: root

    property real widgetWidth: 280
    property real widgetHeight: 200

    property string instanceId: ""
    property var instanceData: null
    readonly property bool lockScreen: true
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})

    readonly property string face: {
        switch (cfg.style ?? "analog") {
        case "analog":
        case "stacked":
        case "expressive":
        case "overlap":
            return cfg.style;
        }
        return "digital";
    }
    readonly property bool analog: face === "analog"
    readonly property bool resizable: true
    property bool forceSquare: analog
    readonly property real defaultScale: lockScreen ? 1.75 : 1

    function baseWidth() {
        switch (face) {
        case "analog":
            return 200;
        case "stacked":
            return 100;
        case "overlap":
            return 160;
        case "expressive":
            return 240;
        }
        return 160;
    }

    function baseHeight() {
        switch (face) {
        case "analog":
        case "overlap":
            return 200;
        case "stacked":
            return 160;
        case "expressive":
            return 120;
        }
        return 70;
    }

    property real defaultWidth: baseWidth() * defaultScale
    property real defaultHeight: baseHeight() * defaultScale
    property real minWidth: {
        switch (face) {
        case "analog":
            return 120;
        case "stacked":
            return 70;
        case "overlap":
            return 80;
        }
        return 100;
    }
    property real minHeight: {
        switch (face) {
        case "analog":
            return 120;
        case "stacked":
        case "overlap":
            return 100;
        }
        return 45;
    }

    enabled: instanceData?.enabled ?? true
    readonly property real transparency: cfg.transparency ?? (lockScreen ? 0 : 0.8)
    readonly property string colorMode: cfg.colorMode ?? (lockScreen ? "default" : "primary")
    readonly property color customColor: cfg.customColor ?? "#ffffff"
    readonly property bool showDate: cfg.showDate ?? !lockScreen
    readonly property bool twoTone: cfg.twoTone ?? lockScreen
    readonly property bool showAnalogNumbers: cfg.showAnalogNumbers ?? false
    readonly property bool showAnalogSeconds: cfg.showAnalogSeconds ?? true
    readonly property bool showDigitalSeconds: cfg.showDigitalSeconds ?? false
    readonly property bool italic: face === "digital" && (cfg.italic ?? false)
    readonly property string fontFamily: cfg.fontFamily || (lockScreen ? SettingsData.lockScreenFontFamily : "")
    readonly property int weight: cfg.weight ?? 0
    readonly property int digitWeight: weight > 0 ? weight : Theme.fontWeight

    readonly property color accentColor: {
        if (lockHost)
            return lockHost.contentColor(colorMode, customColor);
        switch (colorMode) {
        case "secondary":
            return Theme.secondary;
        case "custom":
            return customColor;
        }
        return Theme.primary;
    }
    readonly property color minutesColor: twoTone ? Theme.primary : accentColor
    readonly property color dimColor: Theme.withAlpha(accentColor, 0.65)
    readonly property color backgroundColor: Theme.withAlpha(Theme.hostSurface, transparency)
    readonly property bool themedOverlap: lockScreen && colorMode === "default"
    readonly property var primaryHct: Hct.toHct(Theme.primary)
    readonly property color overlapFaceColor: {
        if (!themedOverlap)
            return accentColor;
        return Theme.isLightMode ? Hct.fromHct(primaryHct.hue, primaryHct.chroma, 65) : Theme.accentOnPrimaryContainer;
    }
    readonly property color overlapShadowColor: {
        if (themedOverlap)
            return Theme.isLightMode ? Hct.fromHct(primaryHct.hue, primaryHct.chroma, 30) : Theme.primaryContainer;
        const source = Hct.toHct(accentColor);
        return Hct.fromHct(source.hue, source.chroma, source.tone > 50 ? 30 : 80);
    }
    readonly property var contrastColors: {
        switch (face) {
        case "overlap":
            return [overlapFaceColor, overlapShadowColor];
        case "digital":
        case "stacked":
        case "expressive":
            return [accentColor, minutesColor];
        }
        return [accentColor];
    }

    readonly property bool needsSeconds: analog ? showAnalogSeconds : showDigitalSeconds
    readonly property string hoursText: {
        const hours = systemClock.date?.getHours() ?? 0;
        const display = SettingsData.use24HourClock ? hours : (hours % 12 || 12);
        return SettingsData.use24HourClock || SettingsData.padHours12Hour ? String(display).padStart(2, "0") : String(display);
    }
    readonly property string minutesText: String(systemClock.date?.getMinutes() ?? 0).padStart(2, "0")
    readonly property string secondsText: String(systemClock.date?.getSeconds() ?? 0).padStart(2, "0")
    readonly property string meridiem: (systemClock.date?.getHours() ?? 0) >= 12 ? "PM" : "AM"
    readonly property string dateFormat: SettingsData.lockDateFormat
    readonly property string formattedDate: systemClock.date?.toLocaleDateString(I18n.locale(), dateFormat || "ddd, MMM d") ?? ""

    SystemClock {
        id: systemClock
        precision: root.needsSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    component DigitText: StyledText {
        font.weight: root.digitWeight
        font.italic: root.italic
        font.family: root.fontFamily !== "" ? root.fontFamily : resolvedFontFamily
        font.features: ({
                "tnum": 1
            })
        color: root.accentColor
        horizontalAlignment: Text.AlignHCenter
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: root.backgroundColor
        visible: !root.analog
    }

    Loader {
        anchors.fill: parent
        anchors.margins: root.analog ? 0 : Theme.spacingM
        sourceComponent: {
            switch (root.face) {
            case "analog":
                return analogClock;
            case "stacked":
                return stackedClock;
            case "expressive":
                return expressiveClock;
            case "overlap":
                return overlapClock;
            }
            return digitalClock;
        }
    }

    Component {
        id: analogClock

        DankAnalogClock {
            hours: systemClock.date?.getHours() ?? 0
            minutes: systemClock.date?.getMinutes() ?? 0
            seconds: systemClock.date?.getSeconds() ?? 0
            showSeconds: root.showAnalogSeconds
            showNumbers: root.showAnalogNumbers
            dateText: root.showDate ? root.formattedDate : ""
            color: root.accentColor
            backgroundColor: root.backgroundColor
        }
    }

    Component {
        id: expressiveClock

        DankClockFace {
            readonly property bool tallBox: height > width * 0.6

            hours: root.hoursText
            minutes: root.minutesText
            seconds: root.showDigitalSeconds && !tallBox ? root.secondsText : ""
            dateText: root.showDate ? root.formattedDate : ""
            stacked: tallBox
            color: root.accentColor
            minutesColor: root.minutesColor
            supportingColor: root.dimColor
        }
    }

    Component {
        id: overlapClock

        Item {
            DankOverlapClockFace {
                anchors.centerIn: parent
                width: implicitWidth
                height: implicitHeight
                hours: root.hoursText
                minutes: root.minutesText
                color: root.overlapFaceColor
                shadowColor: root.overlapShadowColor
                fontFamily: root.fontFamily
                weight: root.weight > 0 ? root.weight : 1000
                scale: implicitWidth > 0 && implicitHeight > 0 ? Math.min(parent.width / implicitWidth, parent.height / implicitHeight) : 1
                renderScale: scale
            }
        }
    }

    Component {
        id: digitalClock

        Item {
            id: digitalRoot

            readonly property bool hasAmPm: !SettingsData.use24HourClock
            readonly property real verticalScale: root.showDate && hasAmPm ? 0.55 : (root.showDate || hasAmPm ? 0.65 : 0.8)
            readonly property real baseSize: Math.min(height * verticalScale, width * 0.22)
            readonly property real digitWidth: baseSize * 0.62
            readonly property real smallSize: baseSize * 0.35

            Column {
                anchors.centerIn: parent
                spacing: 0

                DigitText {
                    visible: root.showDate
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.formattedDate
                    font.pixelSize: digitalRoot.smallSize
                    color: root.dimColor
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0

                    Repeater {
                        model: root.hoursText.split("")

                        DigitText {
                            required property string modelData
                            width: digitalRoot.digitWidth
                            text: modelData
                            font.pixelSize: digitalRoot.baseSize
                        }
                    }

                    DigitText {
                        text: ":"
                        font.pixelSize: digitalRoot.baseSize
                    }

                    Repeater {
                        model: root.minutesText.split("")

                        DigitText {
                            required property string modelData
                            width: digitalRoot.digitWidth
                            text: modelData
                            font.pixelSize: digitalRoot.baseSize
                            color: root.minutesColor
                        }
                    }

                    DigitText {
                        visible: root.showDigitalSeconds
                        text: ":"
                        font.pixelSize: digitalRoot.baseSize
                        color: root.dimColor
                    }

                    Repeater {
                        model: root.showDigitalSeconds ? root.secondsText.split("") : []

                        DigitText {
                            required property string modelData
                            width: digitalRoot.digitWidth
                            text: modelData
                            font.pixelSize: digitalRoot.baseSize
                            color: root.dimColor
                        }
                    }
                }

                DigitText {
                    visible: digitalRoot.hasAmPm
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.meridiem
                    font.pixelSize: digitalRoot.smallSize
                    color: root.dimColor
                }
            }
        }
    }

    Component {
        id: stackedClock

        Item {
            id: stackedRoot

            readonly property bool hasAmPm: !SettingsData.use24HourClock
            readonly property real extraContent: (root.showDigitalSeconds ? 0.12 : 0) + (root.showDate ? 0.08 : 0) + (hasAmPm ? 0.08 : 0)
            readonly property real baseSize: height * (0.42 - extraContent * 0.5)
            readonly property real digitWidth: baseSize * 0.58
            readonly property real smallSize: baseSize * 0.5
            readonly property real rowSpacing: -baseSize * 0.17

            Column {
                anchors.centerIn: parent
                spacing: 0

                Column {
                    spacing: stackedRoot.rowSpacing
                    anchors.horizontalCenter: parent.horizontalCenter

                    Row {
                        spacing: 0
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: root.hoursText.padStart(2, "0").split("")

                            DigitText {
                                required property string modelData
                                width: stackedRoot.digitWidth
                                text: modelData
                                font.pixelSize: stackedRoot.baseSize
                            }
                        }
                    }

                    Row {
                        spacing: 0
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: root.minutesText.split("")

                            DigitText {
                                required property string modelData
                                width: stackedRoot.digitWidth
                                text: modelData
                                font.pixelSize: stackedRoot.baseSize
                                color: root.minutesColor
                            }
                        }
                    }
                }

                Row {
                    visible: root.showDigitalSeconds
                    spacing: 0
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: root.showDigitalSeconds ? root.secondsText.split("") : []

                        DigitText {
                            required property string modelData
                            width: stackedRoot.smallSize * 0.58
                            text: modelData
                            font.pixelSize: stackedRoot.smallSize
                            color: root.dimColor
                        }
                    }
                }

                Item {
                    width: 1
                    height: stackedRoot.baseSize * 0.1
                    visible: root.showDate
                }

                DigitText {
                    visible: root.showDate
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: systemClock.date?.toLocaleDateString(I18n.locale(), "MMM dd") ?? ""
                    font.pixelSize: stackedRoot.smallSize * 0.7
                    color: root.dimColor
                }

                DigitText {
                    visible: stackedRoot.hasAmPm
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.meridiem
                    font.pixelSize: stackedRoot.smallSize * 0.7
                    color: root.dimColor
                }
            }
        }
    }
}
