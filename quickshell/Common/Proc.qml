pragma Singleton

import Quickshell
import qs.DCommon.Common as DCommon

Singleton {
    readonly property string dmsBin: DCommon.Proc.dmsBin

    function runCommand(id, command, callback, debounceMs, timeoutMs) {
        DCommon.Proc.runCommand(id, command, callback, debounceMs, timeoutMs);
    }
}
