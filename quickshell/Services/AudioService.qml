pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool sinkSilent: !!sink?.audio && (sink.audio.muted || sink.audio.volume === 0)
    readonly property string sinkVolumeIconName: {
        const audio = sink?.audio;
        if (!audio)
            return "volume_up";
        if (audio.muted)
            return "volume_off";
        if (audio.volume === 0)
            return "volume_mute";
        return audio.volume * 100 < 33 ? "volume_down" : "volume_up";
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
}
