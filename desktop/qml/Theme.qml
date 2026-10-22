pragma Singleton

import QtQuick

// Material 3 design tokens and the sakura palette (generated from #ff7aa8).
QtObject {
    id: root

    property string mode: "system" // system | dark | light
    onModeChanged: {
        if (Qt.platform.os === "windows")
            Application.styleHints.colorScheme = mode === "system" ? Qt.ColorScheme.Unknown
                : mode === "dark" ? Qt.ColorScheme.Dark : Qt.ColorScheme.Light;
    }
    readonly property bool dark: mode === "dark" || (mode === "system" && Application.styleHints.colorScheme !== Qt.ColorScheme.Light)
    readonly property var palette: dark ? darkPalette : lightPalette

    readonly property var darkPalette: ({
            primary: "#ff89b0", onPrimary: "#610030", primaryContainer: "#ff6fa3", onPrimaryContainer: "#4c0024", inversePrimary: "#b22161",
            secondary: "#ff8ed2", onSecondary: "#63054a", secondaryContainer: "#7d2160", onSecondaryContainer: "#ffbde0",
            tertiary: "#a39eff", onTertiary: "#201083", tertiaryContainer: "#958efb", onTertiaryContainer: "#14006d",
            error: "#ff6e84", onError: "#490013", errorContainer: "#a70138", onErrorContainer: "#ffb2b9",
            background: "#130d0e", onBackground: "#f6e0e4", surface: "#130d0e", surfaceDim: "#130d0e", surfaceBright: "#36292c",
            surfaceContainerLowest: "#000000", surfaceContainerLow: "#191113", surfaceContainer: "#211719",
            surfaceContainerHigh: "#271d1f", surfaceContainerHighest: "#2f2226",
            onSurface: "#f6e0e4", surfaceVariant: "#2f2226", onSurfaceVariant: "#baa6aa", inverseSurface: "#fff8f8", inverseOnSurface: "#5c5354",
            outline: "#827175", outlineVariant: "#534448", shadow: "#000000", scrim: "#000000",
            success: "#7fdc9b", onSuccess: "#00391b"
        })
    readonly property var lightPalette: ({
            primary: "#ad1c5e", onPrimary: "#ffeff1", primaryContainer: "#ff6fa3", onPrimaryContainer: "#4c0024", inversePrimary: "#fe5f9b",
            secondary: "#963776", onSecondary: "#ffeef4", secondaryContainer: "#ffbfe1", onSecondaryContainer: "#7d2160",
            tertiary: "#544db6", onTertiary: "#f5f1ff", tertiaryContainer: "#aca7ff", onTertiaryContainer: "#281b89",
            error: "#b41340", onError: "#ffefef", errorContainer: "#f74b6d", onErrorContainer: "#510017",
            background: "#fff8f8", onBackground: "#3c2f32", surface: "#fff8f8", surfaceDim: "#ead5d9", surfaceBright: "#fff8f8",
            surfaceContainerLowest: "#ffffff", surfaceContainerLow: "#fff0f2", surfaceContainer: "#fce9ed",
            surfaceContainerHigh: "#f7e3e7", surfaceContainerHighest: "#f3dde1",
            onSurface: "#3c2f32", surfaceVariant: "#f3dde1", onSurfaceVariant: "#6b5b5f", inverseSurface: "#130d0e", inverseOnSurface: "#a69a9c",
            outline: "#88767a", outlineVariant: "#c1adb1", shadow: "#000000", scrim: "#000000",
            success: "#1f6d3b", onSuccess: "#ffffff"
        })

    component Rounding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
        readonly property int full: 10000
    }
    component Spacing: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraExtraLarge: 48
    }
    component Padding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
    }

    component Durations: QtObject {
        readonly property int small: 200
        readonly property int normal: 400
        readonly property int large: 600
        readonly property int extraLarge: 1000
        readonly property int expressiveFastSpatial: 350
        readonly property int expressiveDefaultSpatial: 500
        readonly property int expressiveSlowSpatial: 650
        readonly property int expressiveFastEffects: 150
        readonly property int expressiveDefaultEffects: 200
        readonly property int expressiveSlowEffects: 300
    }
    component Motion: QtObject {
        readonly property Durations durations: Durations {}
        readonly property var emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property var emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property var standard: [0.2, 0, 0, 1, 1, 1]
        readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
        readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
        readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
        readonly property var expressiveFastEffects: [0.31, 0.94, 0.34, 1, 1, 1]
        readonly property var expressiveDefaultEffects: [0.34, 0.8, 0.34, 1, 1, 1]
        readonly property var expressiveSlowEffects: [0.34, 0.88, 0.34, 1, 1, 1]
    }

    readonly property Rounding rounding: Rounding {}
    readonly property Spacing spacing: Spacing {}
    readonly property Padding padding: Padding {}
    readonly property Motion anim: Motion {}

    readonly property string family: "Google Sans Flex"
    readonly property string iconFamily: "Material Symbols Rounded"

    function textFont(size: real, weight: int): font {
        return Qt.font({
            family: family,
            pointSize: size,
            weight: weight,
            // Windows' default hints small text to the pixel grid (GDI classic), which looks harsh;
            // this is DirectWrite's natural mode there and FreeType's light hinting on Linux.
            hintingPreference: Font.PreferVerticalHinting,
            variableAxes: {
                "ROND": 25,
                "opsz": size
            }
        });
    }

    component FontScale: QtObject {
        property font large
        property font medium
        property font small
    }
    component Fonts: QtObject {
        property FontScale display
        property FontScale headline
        property FontScale title
        property FontScale body
        property FontScale label
    }
    readonly property Fonts font: Fonts {
        display: FontScale {
            large: root.textFont(42, 600)
            medium: root.textFont(34, 600)
        }
        headline: FontScale {
            large: root.textFont(28, 600)
            medium: root.textFont(24, 550)
            small: root.textFont(20, 550)
        }
        title: FontScale {
            large: root.textFont(17, 500)
            medium: root.textFont(13, 500)
            small: root.textFont(11, 500)
        }
        body: FontScale {
            large: root.textFont(12, 400)
            medium: root.textFont(10.5, 400)
            small: root.textFont(9.5, 400)
        }
        label: FontScale {
            large: root.textFont(10.5, 500)
            medium: root.textFont(9.5, 500)
            small: root.textFont(8.5, 500)
        }
    }

    function alpha(c: color, a: real): color {
        return Qt.alpha(c, a);
    }

    function formatBytes(n: real): string {
        if (!n)
            return "0 MB";
        return n > 1073741824 ? (n / 1073741824).toFixed(2) + " GB" : (n / 1048576).toFixed(1) + " MB";
    }

    function formatTime(sec: real): string {
        sec = Math.max(0, Math.floor(sec || 0));
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
        return (h > 0 ? h + ":" : "") + mm + ":" + String(s).padStart(2, "0");
    }
}
