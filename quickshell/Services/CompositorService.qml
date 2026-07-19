pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string niriSocket: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property string hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""
    readonly property string desktop: (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").split(":")[0].toLowerCase()

    readonly property bool isNiri: niriSocket.length > 0 || desktop === "niri"
    readonly property bool isHyprland: !isNiri && (hyprlandSignature.length > 0 || desktop === "hyprland")

    readonly property string compositor: {
        if (isNiri)
            return "niri";
        if (isHyprland)
            return "hyprland";
        return "unknown";
    }
}
