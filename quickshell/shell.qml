//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Material
//@ pragma UseQApplication
//@ pragma AppId com.danklinux.dms-greeter

import QtQuick
import Quickshell
import qs.Common
import qs.DankCommon.Common as DC
import qs.Modules.Greetd
import qs.Services

ShellRoot {
    id: root

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;
    }

    GreeterSurface {}
}
