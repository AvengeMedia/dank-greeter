pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.DankCommon.Common as DankCommon
import qs.Modules.Greetd
import qs.Services
import "StockThemes.js" as StockThemes

Singleton {
    id: root
    readonly property var log: Log.scoped("Theme")

    readonly property string defaultFontFamily: "Inter Variable"
    readonly property string defaultMonoFontFamily: "Fira Code"
    readonly property string shellDir: Paths.strip(Qt.resolvedUrl(".").toString()).replace("/Common/", "")

    readonly property string dynamic: "dynamic"
    readonly property string custom: "custom"

    property string currentTheme: "purple"
    property bool isLightMode: SessionData.isLightMode
    property var matugenColors: ({})
    property var customThemeData: null
    property var customThemeRawData: null

    onIsLightModeChanged: {
        if (currentTheme === custom && customThemeRawData)
            loadCustomTheme(customThemeRawData);
    }

    function applyGreeterTheme(themeName) {
        switchTheme(themeName);
        if (themeName === dynamic && dynamicColorsFileView.path)
            dynamicColorsFileView.reload();
    }

    function switchTheme(themeName) {
        currentTheme = themeName;
        if (themeName !== custom)
            return;
        if (typeof GreetdSettings !== "undefined" && GreetdSettings.customThemeFile)
            loadCustomThemeFromFile(GreetdSettings.customThemeFile);
    }

    function getMatugenColor(path, fallback) {
        let cur = matugenColors && matugenColors.colors && matugenColors.colors[isLightMode ? "light" : "dark"];
        for (const part of path.split(".")) {
            if (!cur || typeof cur !== "object" || !(part in cur))
                return fallback;
            cur = cur[part];
        }
        return cur || fallback;
    }

    readonly property var currentThemeData: {
        switch (currentTheme) {
        case custom:
            return customThemeData || StockThemes.getThemeByName("purple", isLightMode);
        case dynamic:
            return {
                "primary": getMatugenColor("primary", "#42a5f5"),
                "primaryText": getMatugenColor("on_primary", "#ffffff"),
                "primaryContainer": getMatugenColor("primary_container", "#1976d2"),
                "secondary": getMatugenColor("secondary", "#8ab4f8"),
                "secondaryContainer": getMatugenColor("secondary_container", getMatugenColor("surface_container_high", "#292b2f")),
                "tertiary": getMatugenColor("tertiary", "#efb8c8"),
                "tertiaryContainer": getMatugenColor("tertiary_container", getMatugenColor("surface_container_high", "#292b2f")),
                "surface": getMatugenColor("surface", "#1a1c1e"),
                "surfaceText": getMatugenColor("on_background", "#e3e8ef"),
                "surfaceVariant": getMatugenColor("surface_variant", "#44464f"),
                "surfaceVariantText": getMatugenColor("on_surface_variant", "#c4c7c5"),
                "surfaceTint": getMatugenColor("surface_tint", "#8ab4f8"),
                "background": getMatugenColor("background", "#1a1c1e"),
                "backgroundText": getMatugenColor("on_background", "#e3e8ef"),
                "outline": getMatugenColor("outline", "#8e918f"),
                "surfaceContainerLowest": getMatugenColor("surface_container_lowest", "#0e1013"),
                "surfaceContainerLow": getMatugenColor("surface_container_low", "#181a1d"),
                "surfaceContainer": getMatugenColor("surface_container", "#1e2023"),
                "surfaceContainerHigh": getMatugenColor("surface_container_high", "#292b2f"),
                "surfaceContainerHighest": getMatugenColor("surface_container_highest", "#343740"),
                "error": "#F2B8B5",
                "warning": "#FF9800",
                "info": "#2196F3",
                "success": "#4CAF50"
            };
        default:
            return StockThemes.getThemeByName(currentTheme, isLightMode);
        }
    }

    function loadCustomTheme(themeData) {
        customThemeRawData = themeData;
        const colorMode = isLightMode ? "light" : "dark";

        let baseColors = themeData;
        if (themeData.dark || themeData.light)
            baseColors = themeData[colorMode] || themeData.dark || themeData.light || {};

        if (!themeData.variants) {
            customThemeData = baseColors;
            return;
        }

        const themeId = themeData.id || "";
        const storedVariants = (typeof GreetdSettings !== "undefined" && GreetdSettings.registryThemeVariants) || ({});

        if (themeData.variants.type === "multi" && themeData.variants.flavors && themeData.variants.accents) {
            const defaults = themeData.variants.defaults || {};
            const modeDefaults = defaults[colorMode] || defaults.dark || {};
            const stored = storedVariants[themeId]?.[colorMode] || modeDefaults;
            let flavorId = stored.flavor || modeDefaults.flavor || "";
            const accentId = stored.accent || modeDefaults.accent || "";
            let flavor = findVariant(themeData.variants.flavors, flavorId);
            if (flavor) {
                const hasCurrentModeColors = flavor[colorMode] && (flavor[colorMode].primary || flavor[colorMode].surface);
                if (!hasCurrentModeColors) {
                    flavorId = modeDefaults.flavor || "";
                    flavor = findVariant(themeData.variants.flavors, flavorId);
                }
            }
            const accent = findAccent(themeData.variants.accents, accentId);
            if (flavor)
                baseColors = mergeColors(baseColors, flavor[colorMode] || flavor.dark || flavor.light || {});
            if (accent && flavor)
                baseColors = mergeColors(baseColors, accent[flavor.id] || {});
            customThemeData = baseColors;
            return;
        }

        if (themeData.variants.options && themeData.variants.options.length > 0) {
            const selectedVariantId = typeof storedVariants[themeId] === "string" ? storedVariants[themeId] : themeData.variants.default;
            const variant = findVariant(themeData.variants.options, selectedVariantId);
            if (variant) {
                customThemeData = mergeColors(baseColors, variant[colorMode] || variant.dark || variant.light || {});
                return;
            }
        }

        customThemeData = baseColors;
    }

    function findVariant(options, variantId) {
        if (!variantId || !options)
            return null;
        for (let i = 0; i < options.length; i++) {
            if (options[i].id === variantId)
                return options[i];
        }
        return options[0] || null;
    }

    function findAccent(accents, accentId) {
        if (!accentId || !accents)
            return null;
        for (let i = 0; i < accents.length; i++) {
            if (accents[i].id === accentId)
                return accents[i];
        }
        return accents[0] || null;
    }

    function mergeColors(base, overlay) {
        const result = JSON.parse(JSON.stringify(base));
        for (const key in overlay) {
            if (overlay[key])
                result[key] = overlay[key];
        }
        return result;
    }

    function loadCustomThemeFromFile(filePath) {
        customThemeFileView.path = Paths.expandTilde(filePath);
    }

    property color primary: currentThemeData.primary
    property color primaryText: currentThemeData.primaryText
    property color secondary: currentThemeData.secondary
    property color tertiary: currentThemeData.tertiary || currentThemeData.secondary
    property color surface: currentThemeData.surface
    property color surfaceText: currentThemeData.surfaceText
    property color surfaceVariant: currentThemeData.surfaceVariant
    property color surfaceVariantText: currentThemeData.surfaceVariantText
    property color surfaceTint: currentThemeData.surfaceTint
    property color background: currentThemeData.background
    property color backgroundText: currentThemeData.backgroundText
    property color outline: currentThemeData.outline
    property color outlineVariant: currentThemeData.outlineVariant || withAlpha(outline, 0.6)
    property color surfaceContainerLowest: currentThemeData.surfaceContainerLowest || blend(surfaceContainer, surface, 1.2)
    property color surfaceContainerLow: currentThemeData.surfaceContainerLow || blend(surface, surfaceContainer, 0.667)
    property color surfaceContainer: currentThemeData.surfaceContainer
    property color surfaceContainerHigh: currentThemeData.surfaceContainerHigh
    property color surfaceContainerHighest: currentThemeData.surfaceContainerHighest || surfaceContainerHigh
    property color primaryContainer: currentThemeData.primaryContainer || blend(surfaceContainerHigh, primary, 0.45)
    property color secondaryContainer: currentThemeData.secondaryContainer || blend(surfaceContainerHigh, secondary, 0.35)
    property color tertiaryContainer: currentThemeData.tertiaryContainer || blend(surfaceContainerHigh, tertiary, 0.35)

    property color onSurface: surfaceText
    property color onSurfaceVariant: surfaceVariantText
    property color onPrimary: primaryText
    property color onSurface_12: withAlpha(onSurface, 0.12)
    property color onSurface_38: withAlpha(onSurface, 0.38)
    property color onSurfaceVariant_30: withAlpha(onSurfaceVariant, 0.30)

    property color error: currentThemeData.error || "#F2B8B5"
    property color warning: currentThemeData.warning || "#FF9800"
    property color info: currentThemeData.info || "#2196F3"
    property color success: currentThemeData.success || "#4CAF50"

    property color primaryHover: withAlpha(primary, 0.12)
    property color primaryHoverLight: withAlpha(primary, 0.08)
    property color primaryPressed: withAlpha(primary, 0.16)
    property color primarySelected: withAlpha(primary, 0.3)
    property color primaryBackground: withAlpha(primary, 0.04)

    property color secondaryHover: withAlpha(secondary, 0.08)

    property color surfaceHover: withAlpha(surfaceVariant, 0.08)
    property color surfacePressed: withAlpha(surfaceVariant, 0.12)
    property color surfaceSelected: withAlpha(surfaceVariant, 0.15)
    property color surfaceLight: withAlpha(surfaceVariant, 0.1)
    property color surfaceVariantAlpha: withAlpha(surfaceVariant, 0.2)

    property color surfaceTextHover: withAlpha(surfaceText, 0.08)
    property color surfaceTextAlpha: withAlpha(surfaceText, 0.3)
    property color surfaceTextLight: withAlpha(surfaceText, 0.06)
    property color surfaceTextSecondary: withAlpha(surfaceText, 0.6)
    property color surfaceTextMedium: withAlpha(surfaceText, 0.7)

    property color outlineButton: withAlpha(outline, 0.5)
    property color outlineLight: withAlpha(outline, 0.075)
    property color outlineMedium: withAlpha(outline, 0.12)
    property color outlineStrong: withAlpha(outline, 0.18)
    property color outlineHeavy: withAlpha(outline, 0.2)

    property color errorHover: withAlpha(error, 0.12)
    property color errorPressed: withAlpha(error, 0.16)
    property color errorSelected: withAlpha(error, 0.3)
    property color warningHover: withAlpha(warning, 0.12)

    property color shadowMedium: Qt.rgba(0, 0, 0, 0.08)
    property color shadowStrong: Qt.rgba(0, 0, 0, 0.3)

    property color buttonBg: primary
    property color buttonText: primaryText
    property color buttonHover: primaryHover
    property color buttonPressed: primaryPressed

    property real popupTransparency: 1.0
    readonly property color floatingSurface: withAlpha(surfaceContainer, popupTransparency)
    readonly property color nestedSurface: withAlpha(surfaceContainerHigh, popupTransparency)

    property color widgetBaseHoverColor: {
        const blended = blend(surfaceContainerHigh, primary, 0.1);
        return withAlpha(blended, Math.max(0.3, blended.a));
    }

    readonly property bool elevationEnabled: true
    readonly property string elevationLightDirection: "top"
    readonly property real _elevDiagRatio: 0.55

    readonly property var elevationLevel1: ({
            blurPx: 4,
            offsetX: 0,
            offsetY: 1,
            spreadPx: 0,
            alpha: 0.2
        })
    readonly property var elevationLevel2: ({
            blurPx: 8,
            offsetX: 0,
            offsetY: 4,
            spreadPx: 0,
            alpha: 0.25
        })
    readonly property var elevationLevel3: ({
            blurPx: 12,
            offsetX: 0,
            offsetY: 6,
            spreadPx: 0,
            alpha: 0.3
        })
    readonly property var elevationLevel4: ({
            blurPx: 16,
            offsetX: 0,
            offsetY: 8,
            spreadPx: 0,
            alpha: 0.3
        })
    readonly property var elevationLevel5: ({
            blurPx: 20,
            offsetX: 0,
            offsetY: 10,
            spreadPx: 0,
            alpha: 0.3
        })

    function normalizeElevationDirection(direction) {
        switch (direction) {
        case "top":
        case "topLeft":
        case "topRight":
        case "bottom":
        case "bottomLeft":
        case "bottomRight":
        case "left":
        case "right":
        case "autoBar":
            return direction;
        default:
            return "top";
        }
    }

    function elevationOffsetMagnitude(level, fallback, direction) {
        if (!level)
            return fallback !== undefined ? Math.abs(fallback) : 0;
        const yMag = Math.abs(level.offsetY !== undefined ? level.offsetY : 0);
        if (yMag > 0)
            return yMag;
        const xMag = Math.abs(level.offsetX !== undefined ? level.offsetX : 0);
        if (xMag > 0) {
            if (direction === "left" || direction === "right")
                return xMag;
            return xMag / _elevDiagRatio;
        }
        return fallback !== undefined ? Math.abs(fallback) : 0;
    }

    function elevationOffsetXFor(level, direction, fallback) {
        const dir = normalizeElevationDirection(direction || elevationLightDirection);
        const mag = elevationOffsetMagnitude(level, fallback, dir);
        switch (dir) {
        case "topLeft":
        case "bottomLeft":
            return mag * _elevDiagRatio;
        case "topRight":
        case "bottomRight":
            return -mag * _elevDiagRatio;
        case "left":
            return mag;
        case "right":
            return -mag;
        default:
            return 0;
        }
    }

    function elevationOffsetYFor(level, direction, fallback) {
        const dir = normalizeElevationDirection(direction || elevationLightDirection);
        const mag = elevationOffsetMagnitude(level, fallback, dir);
        switch (dir) {
        case "bottom":
        case "bottomLeft":
        case "bottomRight":
            return -mag;
        case "left":
        case "right":
            return 0;
        default:
            return mag;
        }
    }

    function elevationShadowColor(level) {
        const alpha = (level && level.alpha !== undefined) ? level.alpha : 0.3;
        return Qt.rgba(0, 0, 0, alpha);
    }

    function elevationAmbient(level) {
        const blur = (level && level.blurPx !== undefined) ? Math.max(0, level.blurPx) : 0;
        const alpha = ((level && level.alpha !== undefined) ? level.alpha : 0.3) * 0.5;
        return {
            blurPx: blur * 1.75,
            spreadPx: 1,
            alpha: alpha
        };
    }

    readonly property var animationDurations: [
        {
            "shorter": 0,
            "short": 0,
            "medium": 0,
            "long": 0,
            "extraLong": 0
        },
        {
            "shorter": 50,
            "short": 75,
            "medium": 150,
            "long": 250,
            "extraLong": 500
        },
        {
            "shorter": 100,
            "short": 150,
            "medium": 300,
            "long": 500,
            "extraLong": 1000
        },
        {
            "shorter": 150,
            "short": 225,
            "medium": 450,
            "long": 750,
            "extraLong": 1500
        },
        {
            "shorter": 200,
            "short": 300,
            "medium": 600,
            "long": 1000,
            "extraLong": 2000
        }
    ]

    readonly property int currentAnimationSpeed: SettingsData.animationSpeed
    readonly property bool _customAnimationSpeed: SettingsData.animationSpeed === SettingsData.AnimationSpeed.Custom
    readonly property var currentDurations: animationDurations[currentAnimationSpeed] || animationDurations[SettingsData.AnimationSpeed.Short]

    readonly property int shorterDuration: _customAnimationSpeed ? SettingsData.customAnimationDuration : currentDurations.shorter
    readonly property int shortDuration: _customAnimationSpeed ? SettingsData.customAnimationDuration : currentDurations.short
    readonly property int mediumDuration: _customAnimationSpeed ? SettingsData.customAnimationDuration : currentDurations.medium
    readonly property int longDuration: _customAnimationSpeed ? SettingsData.customAnimationDuration : currentDurations.long
    readonly property int extraLongDuration: _customAnimationSpeed ? SettingsData.customAnimationDuration : currentDurations.extraLong
    readonly property int standardEasing: Easing.OutCubic
    readonly property int emphasizedEasing: Easing.OutQuart

    readonly property int currentAnimationBaseDuration: {
        if (_customAnimationSpeed)
            return SettingsData.customAnimationDuration;
        const presetMap = [0, 250, 500, 750];
        return presetMap[SettingsData.animationSpeed] !== undefined ? presetMap[SettingsData.animationSpeed] : 500;
    }

    readonly property var expressiveCurves: ({
            "emphasized": [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
            "emphasizedAccel": [0.3, 0, 0.8, 0.15, 1, 1],
            "emphasizedDecel": [0.05, 0.7, 0.1, 1, 1, 1],
            "standard": [0.2, 0, 0, 1, 1, 1],
            "standardAccel": [0.3, 0, 1, 1, 1, 1],
            "standardDecel": [0, 0, 0, 1, 1, 1],
            "expressiveFastSpatial": [0.42, 1.67, 0.21, 0.9, 1, 1],
            "expressiveDefaultSpatial": [0.38, 1.21, 0.22, 1, 1, 1],
            "expressiveEffects": [0.34, 0.8, 0.34, 1, 1, 1]
        })

    readonly property var expressiveDurations: ({
            "fast": currentAnimationBaseDuration * 0.4,
            "normal": currentAnimationBaseDuration * 0.8,
            "large": currentAnimationBaseDuration * 1.2,
            "extraLarge": currentAnimationBaseDuration * 2.0,
            "expressiveFastSpatial": currentAnimationBaseDuration * 0.7,
            "expressiveDefaultSpatial": currentAnimationBaseDuration,
            "expressiveEffects": currentAnimationBaseDuration * 0.4
        })

    property string fontFamily: typeof GreetdSettings !== "undefined" ? resolvedFontFamily(GreetdSettings.getEffectiveFontFamily()) : DankCommon.Fonts.sans
    property string monoFontFamily: typeof GreetdSettings !== "undefined" ? resolvedMonoFontFamily(GreetdSettings.monoFontFamily) : DankCommon.Fonts.mono
    property int fontWeight: typeof GreetdSettings !== "undefined" ? GreetdSettings.fontWeight : Font.Normal
    property real fontScale: typeof GreetdSettings !== "undefined" ? GreetdSettings.fontScale : 1.0
    property real cornerRadius: typeof GreetdSettings !== "undefined" ? GreetdSettings.cornerRadius : 12

    function resolvedFontFamily(family) {
        if (family === defaultFontFamily)
            return DankCommon.Fonts.sans;
        return family;
    }

    function resolvedMonoFontFamily(family) {
        if (family === defaultMonoFontFamily)
            return DankCommon.Fonts.mono;
        return family;
    }

    property real spacingXXS: 2
    property real spacingXS: 4
    property real spacingS: 8
    property real spacingM: 12
    property real spacingL: 16
    property real spacingXL: 24
    property real fontSizeSmall: Math.round(fontScale * 12)
    property real fontSizeMedium: Math.round(fontScale * 14)
    property real fontSizeLarge: Math.round(fontScale * 16)
    property real fontSizeXLarge: Math.round(fontScale * 20)
    property real iconSize: 24
    property real iconSizeSmall: 16
    property real iconSizeLarge: 32

    function withAlpha(c, a) {
        if (!c || c.r === undefined)
            return Qt.rgba(0, 0, 0, 0);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function blendAlpha(c, a) {
        if (!c || c.r === undefined)
            return Qt.rgba(0, 0, 0, 0);
        return Qt.rgba(c.r, c.g, c.b, c.a * a);
    }

    function blend(c1, c2, r) {
        return Qt.rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, c1.a * (1 - r) + c2.a * r);
    }

    function getFillMode(modeName) {
        switch (modeName) {
        case "Stretch":
            return Image.Stretch;
        case "Fit":
        case "PreserveAspectFit":
            return Image.PreserveAspectFit;
        case "Fill":
        case "PreserveAspectCrop":
            return Image.PreserveAspectCrop;
        case "Tile":
            return Image.Tile;
        case "TileVertically":
            return Image.TileVertically;
        case "TileHorizontally":
            return Image.TileHorizontally;
        case "Pad":
            return Image.Pad;
        default:
            return Image.PreserveAspectCrop;
        }
    }

    readonly property string _greeterCacheDir: Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter"

    property string greeterColorsBaseDir: root._greeterCacheDir

    function setGreeterColorsBaseDir(dir) {
        const next = dir || root._greeterCacheDir;
        if (greeterColorsBaseDir === next)
            return;
        greeterColorsBaseDir = next;
        dynamicColorsFileView.reload();
    }

    function resetGreeterColorsBaseDir() {
        setGreeterColorsBaseDir(root._greeterCacheDir);
    }

    FileView {
        id: dynamicColorsFileView
        path: root.greeterColorsBaseDir ? (root.greeterColorsBaseDir + "/colors.json") : ""
        blockLoading: false
        watchChanges: false
        printErrors: false

        onLoaded: {
            try {
                const colorsText = dynamicColorsFileView.text();
                if (!colorsText)
                    return;
                root.matugenColors = JSON.parse(colorsText);
            } catch (e) {
                root.log.warn("Failed to parse dynamic colors:", e);
            }
        }
    }

    FileView {
        id: customThemeFileView
        blockLoading: false
        watchChanges: false
        printErrors: false

        onLoaded: {
            try {
                root.loadCustomTheme(JSON.parse(customThemeFileView.text()));
            } catch (e) {
                root.log.warn("Invalid custom theme JSON:", e.message);
            }
        }

        onLoadFailed: function (error) {
            root.log.warn("Failed to read custom theme file:", error);
        }
    }
}
