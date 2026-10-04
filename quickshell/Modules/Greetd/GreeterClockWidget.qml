pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.DankCommon.Session
import "../../DankCommon/Common/Hct.js" as Hct

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property string style: cfg.style ?? "expressive"
    readonly property bool textStyle: style === "horizontal" || style === "vertical"
    readonly property string colorMode: cfg.colorMode ?? "default"
    readonly property var primaryHct: Hct.toHct(Theme.primary)
    readonly property color shadowFaceColor: {
        if (colorMode !== "default")
            return contentColor;
        return Theme.isLightMode ? Hct.fromHct(primaryHct.hue, primaryHct.chroma, 65) : Theme.accentOnPrimaryContainer;
    }
    readonly property color shadowColor: {
        if (colorMode === "default")
            return Theme.isLightMode ? Hct.fromHct(primaryHct.hue, primaryHct.chroma, 30) : Theme.primaryContainer;
        const source = Hct.toHct(shadowFaceColor);
        return Hct.fromHct(source.hue, source.chroma, source.tone > 50 ? 30 : 80);
    }
    readonly property int weightOverride: cfg.weight ?? 0
    readonly property int digitWeight: weightOverride > 0 ? weightOverride : Theme.fontWeight
    readonly property color contentColor: lockHost?.contentColor(cfg.colorMode ?? "default", cfg.customColor ?? "#ffffff") ?? Theme.lockScreenContentColor
    readonly property string fontFamily: cfg.fontFamily || SettingsData.lockScreenFontFamily
    readonly property color minutesColor: (cfg.twoTone ?? true) ? Theme.primary : contentColor
    readonly property var contrastColors: style === "vertical" ? [shadowFaceColor, shadowColor] : style === "horizontal" || style === "expressive" ? [contentColor, minutesColor] : [contentColor]
    readonly property real clockSize: LockMetrics.clockSize * (style === "horizontal" ? 1.5 : 1)
    readonly property real clockDigitWidth: clockSize * 0.625

    readonly property bool resizable: true
    readonly property bool forceSquare: style === "analog"
    readonly property real boxWidth: style === "analog" ? LockMetrics.clockSize * 2 : LockMetrics.clockSize * 4
    readonly property real boxHeight: style === "analog" ? LockMetrics.clockSize * 2 : LockMetrics.clockSize * 1.4
    readonly property real naturalWidth: face.item?.implicitWidth ?? 0
    readonly property real naturalHeight: face.item?.implicitHeight ?? 0
    readonly property real defaultWidth: textStyle ? naturalWidth : boxWidth
    readonly property real defaultHeight: textStyle ? naturalHeight : boxHeight
    readonly property real minWidth: textStyle ? naturalWidth / 2 : LockMetrics.fieldHeight * 2
    readonly property real minHeight: textStyle ? naturalHeight / 2 : LockMetrics.fieldHeight
    readonly property real fitScale: textStyle && naturalWidth > 0 && naturalHeight > 0 ? Math.min(width / naturalWidth, height / naturalHeight) : 1

    implicitWidth: textStyle ? naturalWidth : boxWidth
    implicitHeight: textStyle ? naturalHeight : boxHeight

    component ClockDigitText: StyledText {
        font.pixelSize: root.clockSize
        font.weight: root.digitWeight
        font.italic: root.cfg.italic ?? false
        font.features: ({
                "tnum": 1
            })
        color: root.contentColor
        horizontalAlignment: Text.AlignHCenter
        font.family: root.fontFamily !== "" ? root.fontFamily : resolvedFontFamily
    }

    SystemClock {
        id: systemClock
        precision: (root.style === "analog" ? (root.cfg.showAnalogSeconds ?? true) : SettingsData.getEffectiveTimeFormat().includes("s")) ? SystemClock.Seconds : SystemClock.Minutes
    }

    QtObject {
        id: time

        readonly property string ampm: SettingsData.use24HourClock ? "" : systemClock.date.toLocaleTimeString(I18n.locale(), "AP")
        readonly property string hours: {
            const format = SettingsData.use24HourClock || SettingsData.padHours12Hour ? "hh" : "h";
            const text = systemClock.date.toLocaleTimeString(I18n.locale(), ampm ? format + " AP" : format);
            return ampm ? text.replace(ampm, "").trim() : text;
        }
        readonly property string minutes: systemClock.date.toLocaleTimeString(I18n.locale(), "mm")
        readonly property string seconds: systemClock.date.toLocaleTimeString(I18n.locale(), "ss")
        readonly property bool hasSeconds: SettingsData.showSeconds
    }

    Loader {
        id: face
        anchors.fill: root.textStyle ? undefined : parent
        anchors.centerIn: root.textStyle ? parent : undefined
        width: root.textStyle ? root.naturalWidth : undefined
        height: root.textStyle ? root.naturalHeight : undefined
        scale: root.fitScale
        sourceComponent: {
            switch (root.style) {
            case "vertical":
                return shadowFace;
            case "expressive":
                return expressiveFace;
            case "analog":
                return analogFace;
            }
            return horizontalFace;
        }
    }

    Component {
        id: horizontalFace

        Item {
            implicitWidth: row.implicitWidth
            implicitHeight: row.implicitHeight

            Row {
                id: row
                anchors.centerIn: parent
                layoutDirection: Qt.LeftToRight
                spacing: 0

                ClockDigitText {
                    id: hourText
                    text: time.hours + ":"
                }

                ClockDigitText {
                    text: time.minutes
                    color: root.minutesColor
                }

                ClockDigitText {
                    text: ":" + time.seconds
                    color: root.minutesColor
                    visible: time.hasSeconds
                }

                ClockDigitText {
                    text: " " + time.ampm
                    font.pixelSize: root.clockSize / 3
                    anchors.baseline: hourText.baseline
                    visible: time.ampm !== ""
                }
            }
        }
    }

    Component {
        id: shadowFace

        Item {
            id: shadowItem

            readonly property real digitSize: root.clockSize * 1.25
            readonly property real tracking: -digitSize * 0.1
            readonly property real rowAdvance: digitSize * 0.7
            readonly property int weight: root.weightOverride > 0 ? root.weightOverride : 1000
            readonly property bool variableFont: root.fontFamily === "" || root.fontFamily === Theme.defaultFontFamily
            // One cell width for all four glyphs keeps the columns aligned in fonts without tabular figures.
            readonly property real cellWidth: Math.max(hoursRow.firstAdvance, hoursRow.secondAdvance, minutesRow.firstAdvance, minutesRow.secondAdvance)
            implicitWidth: Math.max(hoursRow.width, minutesRow.width)
            implicitHeight: Math.max(hoursRow.height, minutesRow.y + minutesRow.height)

            ShadowRow {
                id: hoursRow
                x: (shadowItem.width - shadowItem.implicitWidth) / 2
                text: time.hours.padStart(2, "0")
            }

            ShadowRow {
                id: minutesRow
                x: hoursRow.x
                y: hoursRow.baselineOffset + shadowItem.rowAdvance - baselineOffset
                text: time.minutes
                lightFirst: true
            }
        }
    }

    component ClockDigit: StyledText {
        id: digit

        readonly property rect inkBounds: metrics.tightBoundingRect
        readonly property real advanceWidth: metrics.advanceWidth

        font.pixelSize: shadowItem.digitSize
        font.family: root.fontFamily !== "" ? root.fontFamily : Theme.defaultFontFamily
        font.weight: shadowItem.variableFont ? Font.Normal : Math.min(Font.Black, shadowItem.weight)
        font.variableAxes: shadowItem.variableFont ? {
            "wght": shadowItem.weight,
            "ROND": 0,
            "opsz": 18
        } : ({})
        font.features: ({
                "tnum": 1
            })
        textFormat: Text.PlainText
        wrapMode: Text.NoWrap
        elide: Text.ElideNone
        verticalAlignment: Text.AlignTop

        TextMetrics {
            id: metrics
            font: digit.font
            text: digit.text
            renderType: digit.renderType
        }
    }

    component ShadowRow: Item {
        id: shadowRow

        property string text: ""
        property bool lightFirst: false
        readonly property real firstAdvance: firstDigit.advanceWidth
        readonly property real secondAdvance: secondDigit.advanceWidth
        readonly property real cell: shadowItem.cellWidth
        readonly property real topBearing: Math.min(firstDigit.inkBounds.y, secondDigit.inkBounds.y)
        readonly property real bottomBearing: Math.max(firstDigit.inkBounds.y + firstDigit.inkBounds.height, secondDigit.inkBounds.y + secondDigit.inkBounds.height)

        implicitWidth: cell * 2 + shadowItem.tracking
        implicitHeight: bottomBearing - topBearing
        baselineOffset: -topBearing

        ClockDigit {
            id: firstDigit
            x: (shadowRow.cell - advanceWidth) / 2
            y: shadowRow.baselineOffset - baselineOffset
            text: shadowRow.text[0] ?? ""
            color: shadowRow.lightFirst ? root.shadowFaceColor : root.shadowColor
        }

        ClockDigit {
            id: secondDigit
            x: shadowRow.cell + shadowItem.tracking + (shadowRow.cell - advanceWidth) / 2
            y: shadowRow.baselineOffset - baselineOffset
            text: shadowRow.text[1] ?? ""
            color: shadowRow.lightFirst ? root.shadowColor : root.shadowFaceColor
        }
    }

    Component {
        id: expressiveFace

        DankClockFace {
            readonly property bool tallBox: height > width * 0.6

            hours: time.hours
            minutes: time.minutes
            seconds: time.hasSeconds && !tallBox ? time.seconds : ""
            stacked: tallBox
            color: root.contentColor
            minutesColor: root.minutesColor
        }
    }

    Component {
        id: analogFace

        DankAnalogClock {
            hours: systemClock.date?.getHours() ?? 0
            minutes: systemClock.date?.getMinutes() ?? 0
            seconds: systemClock.date?.getSeconds() ?? 0
            showSeconds: root.cfg.showAnalogSeconds ?? true
            showNumbers: root.cfg.showAnalogNumbers ?? false
            color: root.contentColor
            backgroundColor: "transparent"
        }
    }
}
