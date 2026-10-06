import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Session
import "../../DCommon/Common/LayoutCodes.js" as LayoutCodes

Item {
    id: root

    function encodeFileUrl(path) {
        if (!path)
            return "";
        return "file://" + path.split('/').map(s => encodeURIComponent(s)).join('/');
    }

    property Item authWidget: null
    property Item sessionDropdownItem: null
    readonly property bool powerMenuVisible: powerMenu.isVisible

    function clearInput() {
        authWidget?.clearInput();
    }

    function focusInput() {
        authWidget?.focusInput();
    }

    function showPowerMenu() {
        powerMenu.show();
    }

    function contentColor(mode, custom) {
        switch (mode) {
        case "primary":
            return Theme.primary;
        case "secondary":
            return Theme.secondary;
        case "custom":
            return custom;
        }
        return Theme.lockScreenContentColor;
    }

    function cycleKeyboardLayout() {
        if (CompositorService.isNiri) {
            NiriService.cycleKeyboardLayout();
            return;
        }
        if (!CompositorService.isHyprland)
            return;
        Quickshell.execDetached(["hyprctl", "switchxkblayout", hyprlandKeyboard, "next"]);
        updateHyprlandLayout();
    }

    function desktopIdFromPath(path) {
        if (!path)
            return "";
        const parts = path.split("/");
        const id = parts.length > 0 ? parts[parts.length - 1] : path;
        return id || "";
    }

    readonly property string xdgDataDirs: Quickshell.env("XDG_DATA_DIRS")
    property string screenName: ""
    property string hyprlandCurrentLayout: ""
    property string hyprlandKeyboard: ""
    property int hyprlandLayoutCount: 0
    readonly property int keyboardLayoutCount: {
        if (CompositorService.isNiri)
            return NiriService.keyboardLayoutNames.length;
        if (CompositorService.isHyprland)
            return hyprlandLayoutCount;
        return 0;
    }
    readonly property string keyboardLayoutLabel: {
        if (CompositorService.isNiri)
            return LayoutCodes.layoutCode(NiriService.getCurrentKeyboardLayoutName());
        if (CompositorService.isHyprland)
            return hyprlandCurrentLayout;
        return "";
    }
    readonly property string pamState: GreeterState.pamState
    property bool isPrimaryScreen: !Quickshell.screens?.length || screenName === Quickshell.screens[0]?.name

    property bool weatherInitialized: false
    property bool awaitingExternalAuth: false
    property bool pendingPasswordResponse: false
    property bool passwordSubmitRequested: false
    property int defaultAuthTimeoutMs: 10000
    property int externalAuthTimeoutMs: 30000
    property int memoryFlushDelayMs: 120
    property string pendingLaunchCommand: ""
    property var pendingLaunchEnv: []
    property int passwordFailureCount: 0
    property int passwordAttemptLimitHint: 0
    property string authFeedbackMessage: ""
    property string greetdPamText: ""
    property string systemAuthPamText: ""
    property string commonAuthPamText: ""
    property string passwordAuthPamText: ""
    property string systemLoginPamText: ""
    property string systemLocalLoginPamText: ""
    property string commonAuthPcPamText: ""
    property string loginPamText: ""
    property string faillockConfigText: ""
    property string externalAuthAutoStartedForUser: ""
    property bool fprintdProbeComplete: false
    property bool fprintdHasDevice: false
    property bool autoLoginOnSuccess: false
    readonly property bool greeterPamStackHasFprint: greeterPamStackHasModule("pam_fprintd")
    // Falls back to PAM-only detection until the fprintd D-Bus probe completes.
    readonly property bool greeterPamHasFprint: greeterPamStackHasFprint && (!fprintdProbeComplete || fprintdHasDevice)
    readonly property bool greeterPamHasU2f: greeterPamStackHasModule("pam_u2f")
    readonly property bool greeterPamHasFaceAuth: greeterPamStackHasModule("pam_howdy") || greeterPamStackHasModule("pam_sentinel") || greeterPamStackHasModule("pam_face") || greeterPamStackHasModule("pam_smile2unlock")
    readonly property bool greeterPamHasHowdy: greeterPamHasFaceAuth
    readonly property bool greeterExternalAuthAvailable: (greeterPamHasFprint && SettingsData.greeterEnableFprint) || (greeterPamHasU2f && SettingsData.greeterEnableU2f) || greeterPamHasFaceAuth
    readonly property bool greeterPamHasExternalAuth: greeterPamHasFprint || greeterPamHasU2f || greeterPamHasFaceAuth
    readonly property bool externalAuthInProgress: awaitingExternalAuth || (Greetd.state !== GreetdState.Inactive && passwordSubmitRequested && greeterPamHasExternalAuth && !pendingPasswordResponse)
    readonly property string externalAuthStatusMessage: {
        if (!externalAuthInProgress)
            return "";
        if (greeterPamHasFprint && greeterPamHasU2f)
            return I18n.tr("Awaiting fingerprint or security key authentication");
        if (greeterPamHasFprint)
            return I18n.tr("Awaiting fingerprint authentication");
        if (greeterPamHasFaceAuth)
            return I18n.tr("Awaiting face authentication");
        return I18n.tr("Awaiting security key authentication");
    }
    readonly property string authDisplayMessage: authFeedbackMessage || externalAuthStatusMessage
    readonly property bool autoLoginAvailable: GreetdSettings.rememberLastUser && GreetdSettings.rememberLastSession
    readonly property bool multipleUsersAvailable: GreeterUsersService.loaded && GreeterUsersService.users.length > 1
    // Single-user systems get the picker too when auto-login is available, so the
    // auto-login toggle lives inside the dropdown instead of floating on its own.
    readonly property bool pickerAvailable: multipleUsersAvailable || (GreeterUsersService.loaded && GreeterUsersService.users.length === 1 && autoLoginAvailable)
    readonly property bool showUserPicker: pickerAvailable && !GreeterState.showPasswordInput && !manualUsernameEntry
    readonly property bool showAccountSwitchLink: pickerAvailable && manualUsernameEntry && !GreeterState.showPasswordInput && !GreeterState.unlocking
    readonly property int userPickerMaxHeight: Math.min(400, Math.max(120, height * 0.35))
    property bool userListOpen: false
    property bool manualUsernameEntry: false
    property bool skipAutoSelectUser: false
    property string pickerThemeUsername: ""

    function initWeatherService() {
        if (weatherInitialized)
            return;
        if (!GreetdSettings.settingsLoaded)
            return;
        const status = SettingsData.greeterWidgetInstances.find(instance => instance.widgetType === "lockStatus");
        if (!status || status.enabled === false || status.config?.showWeather === false)
            return;
        weatherInitialized = true;
        WeatherService.addRef();
        WeatherService.forceRefresh();
    }

    function stripPamComment(line) {
        if (!line)
            return "";
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#"))
            return "";
        const hashIdx = trimmed.indexOf("#");
        if (hashIdx >= 0)
            return trimmed.substring(0, hashIdx).trim();
        return trimmed;
    }

    function pamModuleEnabled(pamText, moduleName) {
        if (!pamText || !moduleName)
            return false;
        const lines = pamText.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            const line = stripPamComment(lines[i]);
            if (!line)
                continue;
            if (line.includes(moduleName))
                return true;
        }
        return false;
    }

    function pamTextIncludesFile(pamText, filename) {
        if (!pamText || !filename)
            return false;
        const lines = pamText.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            const line = stripPamComment(lines[i]);
            if (!line)
                continue;
            if (line.includes(filename) && (line.includes("include") || line.includes("substack") || line.startsWith("@include")))
                return true;
        }
        return false;
    }

    function greeterPamStackHasModule(moduleName) {
        if (pamModuleEnabled(greetdPamText, moduleName))
            return true;
        const includedPamStacks = [["system-auth", systemAuthPamText], ["common-auth", commonAuthPamText], ["password-auth", passwordAuthPamText], ["system-login", systemLoginPamText], ["system-local-login", systemLocalLoginPamText], ["common-auth-pc", commonAuthPcPamText], ["login", loginPamText]];
        for (let i = 0; i < includedPamStacks.length; i++) {
            const stack = includedPamStacks[i];
            if (pamTextIncludesFile(greetdPamText, stack[0]) && pamModuleEnabled(stack[1], moduleName))
                return true;
        }
        return false;
    }

    function usesPamLockoutPolicy(pamText) {
        if (!pamText)
            return false;
        const lines = pamText.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            const line = stripPamComment(lines[i]);
            if (!line)
                continue;
            if (line.includes("pam_faillock.so") || line.includes("pam_tally2.so") || line.includes("pam_tally.so"))
                return true;
        }
        return false;
    }

    function parsePamLineDenyValue(pamText) {
        if (!pamText)
            return -1;
        const lines = pamText.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            const line = stripPamComment(lines[i]);
            if (!line)
                continue;
            if (!line.includes("pam_faillock.so") && !line.includes("pam_tally2.so") && !line.includes("pam_tally.so"))
                continue;
            const denyMatch = line.match(/\bdeny\s*=\s*(\d+)\b/i);
            if (!denyMatch)
                continue;
            const parsed = parseInt(denyMatch[1], 10);
            if (!isNaN(parsed))
                return parsed;
        }
        return -1;
    }

    function parseFaillockDenyValue(configText) {
        if (!configText)
            return -1;
        const lines = configText.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            const line = stripPamComment(lines[i]);
            if (!line)
                continue;
            const denyMatch = line.match(/^deny\s*=\s*(\d+)\s*$/i);
            if (!denyMatch)
                continue;
            const parsed = parseInt(denyMatch[1], 10);
            if (!isNaN(parsed))
                return parsed;
        }
        return -1;
    }

    function refreshPasswordAttemptPolicyHint() {
        const pamSources = [greetdPamText, systemAuthPamText, commonAuthPamText, passwordAuthPamText, systemLoginPamText, systemLocalLoginPamText, commonAuthPcPamText, loginPamText];
        let lockoutConfigured = false;
        let denyFromPam = -1;
        for (let i = 0; i < pamSources.length; i++) {
            const source = pamSources[i];
            if (!source)
                continue;
            if (usesPamLockoutPolicy(source))
                lockoutConfigured = true;
            const denyValue = parsePamLineDenyValue(source);
            if (denyValue >= 0 && (denyFromPam < 0 || denyValue < denyFromPam))
                denyFromPam = denyValue;
        }

        if (!lockoutConfigured) {
            passwordAttemptLimitHint = 0;
            return;
        }

        const denyFromConfig = parseFaillockDenyValue(faillockConfigText);
        if (denyFromConfig >= 0) {
            passwordAttemptLimitHint = denyFromConfig;
            return;
        }

        if (denyFromPam >= 0) {
            passwordAttemptLimitHint = denyFromPam;
            return;
        }

        // pam_faillock default deny value when no explicit config is set.
        passwordAttemptLimitHint = 3;
    }

    function isLikelyLockoutMessage(message) {
        const lower = (message || "").toLowerCase();
        return lower.includes("account is locked") || lower.includes("too many") || lower.includes("maximum number of");
    }

    function currentAuthMessage() {
        if (GreeterState.pamState === "error")
            return I18n.tr("Authentication error - try again");
        if (GreeterState.pamState === "max")
            return I18n.tr("Too many failed attempts - account may be locked");
        if (GreeterState.pamState === "fail") {
            if (passwordAttemptLimitHint > 0) {
                const attempt = Math.max(1, Math.min(passwordFailureCount, passwordAttemptLimitHint));
                const remaining = Math.max(passwordAttemptLimitHint - attempt, 0);
                if (remaining > 0) {
                    return I18n.tr("Authentication failed - attempt %1 of %2").arg(attempt).arg(passwordAttemptLimitHint);
                }
                return I18n.tr("Authentication failed - lockout can occur");
            }
            return I18n.tr("Authentication failed - try again");
        }
        return "";
    }

    function clearAuthFeedback() {
        GreeterState.pamState = "";
        authFeedbackMessage = "";
    }

    Connections {
        target: GreetdSettings
        function onSettingsLoadedChanged() {
            if (GreetdSettings.settingsLoaded) {
                initWeatherService();
                if (isPrimaryScreen) {
                    applyLastSuccessfulUser();
                    finalizeSessionSelection();
                }
            }
        }

        function onRememberLastUserChanged() {
            if (!isPrimaryScreen)
                return;
            if (!GreetdSettings.rememberLastUser && GreetdMemory.lastSuccessfulUser) {
                GreetdMemory.setLastSuccessfulUser("");
            }
            applyLastSuccessfulUser();
        }

        function onRememberLastSessionChanged() {
            if (!isPrimaryScreen)
                return;
            if (!GreetdSettings.rememberLastSession && (GreetdMemory.lastSessionId || GreetdMemory.lastSessionDesktopId)) {
                GreetdMemory.setLastSession("", "");
            }
            finalizeSessionSelection();
        }
    }

    FileView {
        id: greetdPamWatcher
        path: "/etc/pam.d/greetd"
        printErrors: false
        onLoaded: {
            root.greetdPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.greetdPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: systemAuthPamWatcher
        path: "/etc/pam.d/system-auth"
        printErrors: false
        onLoaded: {
            root.systemAuthPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.systemAuthPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: commonAuthPamWatcher
        path: "/etc/pam.d/common-auth"
        printErrors: false
        onLoaded: {
            root.commonAuthPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.commonAuthPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: passwordAuthPamWatcher
        path: "/etc/pam.d/password-auth"
        printErrors: false
        onLoaded: {
            root.passwordAuthPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.passwordAuthPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: systemLoginPamWatcher
        path: "/etc/pam.d/system-login"
        printErrors: false
        onLoaded: {
            root.systemLoginPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.systemLoginPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: systemLocalLoginPamWatcher
        path: "/etc/pam.d/system-local-login"
        printErrors: false
        onLoaded: {
            root.systemLocalLoginPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.systemLocalLoginPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: commonAuthPcPamWatcher
        path: "/etc/pam.d/common-auth-pc"
        printErrors: false
        onLoaded: {
            root.commonAuthPcPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.commonAuthPcPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: loginPamWatcher
        path: "/etc/pam.d/login"
        printErrors: false
        onLoaded: {
            root.loginPamText = text();
            root.refreshPasswordAttemptPolicyHint();
            root.maybeAutoStartExternalAuth();
        }
        onLoadFailed: {
            root.loginPamText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    FileView {
        id: faillockConfigWatcher
        path: "/etc/security/faillock.conf"
        printErrors: false
        onLoaded: {
            root.faillockConfigText = text();
            root.refreshPasswordAttemptPolicyHint();
        }
        onLoadFailed: {
            root.faillockConfigText = "";
            root.refreshPasswordAttemptPolicyHint();
        }
    }

    Component.onCompleted: {
        initWeatherService();
        refreshPasswordAttemptPolicyHint();

        if (isPrimaryScreen)
            applyLastSuccessfulUser();

        if (CompositorService.isHyprland)
            updateHyprlandLayout();

        fprintdDeviceProbe.running = true;
    }

    function applyPickerPreviewTheme() {
        let previewUser = (pickerThemeUsername || "").trim();
        if (!previewUser && GreetdSettings.rememberLastUser)
            previewUser = (GreetdMemory.lastSuccessfulUser || "").trim();
        if (previewUser)
            GreeterUserTheme.applyForUser(previewUser);
        else
            GreeterUserTheme.applyDefault();
    }

    function applyLastSuccessfulUser() {
        if (root.skipAutoSelectUser)
            return;
        if (!GreetdSettings.settingsLoaded || !GreetdSettings.rememberLastUser)
            return;
        const lastUser = GreetdMemory.lastSuccessfulUser;
        if (lastUser && !GreeterState.showPasswordInput && !GreeterState.username) {
            selectUser(lastUser);
        }
    }

    function enterManualUsernameEntry() {
        if (!root.pickerAvailable || GreeterState.showPasswordInput)
            return;
        root.manualUsernameEntry = true;
        root.userListOpen = false;
        GreeterState.username = "";
        GreeterState.usernameInput = "";
        root.clearInput();
        root.applyPickerPreviewTheme();
        Qt.callLater(root.focusInput);
    }

    function returnToUserListFromManualEntry() {
        if (!root.pickerAvailable)
            return;
        root.manualUsernameEntry = false;
        root.userListOpen = true;
        GreeterState.username = "";
        GreeterState.usernameInput = "";
        root.clearInput();
        root.applyPickerPreviewTheme();
    }

    function returnToUserPicker() {
        if (!root.pickerAvailable || GreeterState.unlocking)
            return;
        root.manualUsernameEntry = false;
        root.skipAutoSelectUser = true;
        awaitingExternalAuth = false;
        pendingPasswordResponse = false;
        passwordSubmitRequested = false;
        authTimeout.interval = defaultAuthTimeoutMs;
        authTimeout.stop();
        clearAuthFeedback();
        passwordFailureCount = 0;
        externalAuthAutoStartedForUser = "";
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        const previousUser = GreeterState.username;
        GreeterState.reset();
        root.clearInput();
        if (previousUser)
            root.pickerThemeUsername = previousUser;
        root.applyPickerPreviewTheme();
        root.userListOpen = true;
    }

    function selectUser(rawValue) {
        const user = (rawValue || "").trim();
        if (!user)
            return;
        root.manualUsernameEntry = false;
        root.skipAutoSelectUser = false;
        submitUsername(user);
    }

    function submitUsername(rawValue) {
        const user = (rawValue || "").trim();
        if (!user)
            return;
        if (GreeterState.username !== user) {
            passwordFailureCount = 0;
            clearAuthFeedback();
            externalAuthAutoStartedForUser = "";
        }
        root.pickerThemeUsername = user;
        GreeterState.username = user;
        GreeterState.usernameInput = user;
        GreeterState.showPasswordInput = true;
        root.userListOpen = false;
        GreeterState.passwordBuffer = "";
        pendingPasswordResponse = false;
        passwordSubmitRequested = false;
        maybeAutoStartExternalAuth();
    }

    function submitBufferedPassword() {
        pendingPasswordResponse = false;
        passwordSubmitRequested = false;
        awaitingExternalAuth = false;
        authTimeout.interval = defaultAuthTimeoutMs;
        authTimeout.restart();
        // Some PAM stacks expect an explicit empty response to advance U2F/fprint or fail normally.
        Greetd.respond(GreeterState.passwordBuffer || "");
        GreeterState.passwordBuffer = "";
        root.clearInput();
        return true;
    }

    function startAuthSession(submitPassword) {
        submitPassword = submitPassword === true;
        if (!GreeterState.showPasswordInput || !GreeterState.username)
            return;
        if (GreeterState.unlocking)
            return;
        const hasPasswordBuffer = GreeterState.passwordBuffer && GreeterState.passwordBuffer.length > 0;
        if (Greetd.state !== GreetdState.Inactive) {
            if (pendingPasswordResponse && submitPassword)
                submitBufferedPassword();
            else if (submitPassword)
                passwordSubmitRequested = true;
            return;
        }
        if (!submitPassword && !hasPasswordBuffer && !root.greeterExternalAuthAvailable)
            return;
        pendingPasswordResponse = false;
        passwordSubmitRequested = submitPassword;
        awaitingExternalAuth = !submitPassword && !hasPasswordBuffer && root.greeterExternalAuthAvailable;
        // Let the effective PAM stack finish external authentication.
        const waitingOnPamExternalBeforePassword = submitPassword && root.greeterPamHasExternalAuth;
        authTimeout.interval = (awaitingExternalAuth || waitingOnPamExternalBeforePassword) ? externalAuthTimeoutMs : defaultAuthTimeoutMs;
        authTimeout.restart();
        Greetd.createSession(GreeterState.username);
    }

    function maybeAutoStartExternalAuth() {
        if (!GreeterState.showPasswordInput || !GreeterState.username)
            return;
        if (!root.greeterExternalAuthAvailable)
            return;
        if (GreeterState.unlocking || Greetd.state !== GreetdState.Inactive)
            return;
        if (passwordSubmitRequested)
            return;
        if (GreeterState.passwordBuffer && GreeterState.passwordBuffer.length > 0)
            return;
        if (externalAuthAutoStartedForUser === GreeterState.username)
            return;

        externalAuthAutoStartedForUser = GreeterState.username;
        startAuthSession(false);
    }

    Component.onDestruction: {
        if (weatherInitialized)
            WeatherService.removeRef();
    }

    function updateHyprlandLayout() {
        if (CompositorService.isHyprland) {
            hyprlandLayoutProcess.running = true;
        }
    }

    Process {
        id: greeterAutoLoginPendingProcess
        command: ["sh", "-c", "mkdir -p $(dirname " + JSON.stringify((Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter") + "/.local/state/auto-login-sync-pending") + ") && touch " + JSON.stringify((Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter") + "/.local/state/auto-login-sync-pending")]
        running: false
    }

    Process {
        id: hyprlandLayoutProcess
        running: false
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const mainKeyboard = data.keyboards.find(kb => kb.main === true);
                    if (!mainKeyboard) {
                        hyprlandCurrentLayout = "";
                        hyprlandLayoutCount = 0;
                        return;
                    }
                    hyprlandKeyboard = mainKeyboard.name;
                    if (mainKeyboard.active_keymap) {
                        hyprlandCurrentLayout = LayoutCodes.layoutCode(mainKeyboard.active_keymap);
                    } else {
                        hyprlandCurrentLayout = "";
                    }
                    hyprlandLayoutCount = mainKeyboard.layout ? mainKeyboard.layout.split(",").length : 0;
                } catch (e) {
                    hyprlandCurrentLayout = "";
                    hyprlandLayoutCount = 0;
                }
            }
        }
    }

    // Probe fprintd D-Bus for physically enrolled scanners to eliminate PAM stack false-positives.
    Process {
        id: fprintdDeviceProbe
        running: false
        // sh wrapper: emits PROBE_UNAVAILABLE if gdbus is absent or fprintd unreachable,
        // keeping the PAM-only fallback active in those cases.
        command: ["sh", "-c", "command -v gdbus >/dev/null 2>&1 || { echo PROBE_UNAVAILABLE; exit 0; }; " + "gdbus call --system " + "--dest net.reactivated.Fprint " + "--object-path /net/reactivated/Fprint/Manager " + "--method net.reactivated.Fprint.Manager.GetDevices 2>/dev/null " + "|| echo PROBE_UNAVAILABLE"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes("PROBE_UNAVAILABLE"))
                    return; // PAM-only fallback stays active
                root.fprintdHasDevice = text.includes("objectpath");
                root.fprintdProbeComplete = true;
                root.maybeAutoStartExternalAuth();
            }
        }
        onExited: function (exitCode, exitStatus) {
            if (!root.fprintdProbeComplete)
                root.maybeAutoStartExternalAuth(); // PAM-only fallback stays active
        }
    }

    Connections {
        target: CompositorService.isHyprland ? Hyprland : null
        enabled: CompositorService.isHyprland

        function onRawEvent(event) {
            if (event.name === "activelayout")
                updateHyprlandLayout();
        }
    }

    Connections {
        target: GreetdMemory
        enabled: isPrimaryScreen
        function onLastSuccessfulUserChanged() {
            applyLastSuccessfulUser();
        }
        function onMemoryReadyChanged() {
            finalizeSessionSelection();
        }
    }

    Connections {
        target: GreeterUsersService
        function onLoadedChanged() {
            if (GreeterUsersService.loaded && isPrimaryScreen)
                applyPickerPreviewTheme();
        }
        function onSyncedThemePathsChanged() {
            if (!isPrimaryScreen)
                return;
            if (GreeterState.username)
                GreeterUserTheme.applyForUser(GreeterState.username);
            else if (root.showUserPicker || root.userListOpen)
                applyPickerPreviewTheme();
        }
    }

    Connections {
        target: GreeterState
        function onUsernameChanged() {
            if (GreeterState.username) {
                root.pickerThemeUsername = GreeterState.username;
                GreeterUserTheme.applyForUser(GreeterState.username);
            } else if (root.showUserPicker || root.userListOpen) {
                applyPickerPreviewTheme();
            }
        }
        function onShowPasswordInputChanged() {
            if (GreeterState.showPasswordInput)
                root.userListOpen = false;
        }
    }

    onShowUserPickerChanged: {
        if (showUserPicker && !GreeterState.username)
            applyPickerPreviewTheme();
        if (!showUserPicker)
            userListOpen = false;
    }

    Rectangle {
        anchors.fill: parent
        color: SettingsData.effectiveWallpaperBackgroundColor
    }

    readonly property bool hasCustomWallpaper: SettingsData.lockScreenWallpaperPath !== ""
    readonly property string wallpaperSource: {
        if (hasCustomWallpaper)
            return encodeFileUrl(GreetdSettings.resolveUserPath(SettingsData.lockScreenWallpaperPath));
        var w = SessionData.getMonitorWallpaper(screenName);
        return (w && !w.startsWith("#")) ? encodeFileUrl(w) : "";
    }
    readonly property string wallpaperFillModeName: {
        if (SettingsData.lockScreenWallpaperFillMode !== "")
            return SettingsData.lockScreenWallpaperFillMode;
        return hasCustomWallpaper ? "Fill" : SessionData.getMonitorWallpaperFillMode(screenName);
    }

    DankBackdrop {
        anchors.fill: parent
        screenName: root.screenName
        blur: Theme.lockScreenBlur
        blurMax: Theme.lockScreenBlurMax
        visible: root.wallpaperSource === "" || wallpaperBackground.status === Image.Error
    }

    Image {
        id: wallpaperBackground

        anchors.fill: parent
        source: root.wallpaperSource
        fillMode: Theme.getFillMode(root.wallpaperFillModeName)
        smooth: true
        asynchronous: false
        cache: true
        visible: source !== ""
        layer.enabled: true

        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: Theme.lockScreenBlur
            blurMax: Theme.lockScreenBlurMax
            blurMultiplier: 1
        }

        Behavior on opacity {
            NumberAnimation {
                duration: LockMetrics.effectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.screenOffColor
        opacity: Theme.lockScreenScrimAlpha
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.userListOpen
        visible: root.userListOpen
        onClicked: root.userListOpen = false
    }

    GreeterWidgetLayer {
        anchors.fill: parent
        focus: true
        screenName: root.screenName
        lockHost: root
    }

    property string currentSessionName: GreeterState.sessionList[GreeterState.currentSessionIndex] || ""

    function finalizeSessionSelection() {
        if (GreeterState.sessionManuallySelected)
            return;
        if (GreeterState.sessionList.length === 0)
            return;
        if (!GreetdMemory.memoryReady)
            return;
        if (!GreetdSettings.settingsLoaded)
            return;

        const savedSession = GreetdSettings.rememberLastSession ? GreetdMemory.lastSessionId : "";
        const savedDesktopId = GreetdSettings.rememberLastSession ? (GreetdMemory.lastSessionDesktopId || desktopIdFromPath(GreetdMemory.lastSessionId)) : "";
        if ((savedSession || savedDesktopId) && GreetdSettings.rememberLastSession) {
            for (var i = 0; i < GreeterState.sessionPaths.length; i++) {
                if ((savedDesktopId && GreeterState.sessionDesktopIds[i] === savedDesktopId) || (savedSession && GreeterState.sessionPaths[i] === savedSession)) {
                    GreeterState.currentSessionIndex = i;
                    GreeterState.selectedSession = GreeterState.sessionExecs[i] || "";
                    GreeterState.selectedSessionPath = GreeterState.sessionPaths[i];
                    GreeterState.selectedSessionDesktopId = GreeterState.sessionDesktopIds[i] || "";
                    GreeterState.selectedSessionDesktopNames = GreeterState.sessionDesktopNames[i] || "";
                    return;
                }
            }
        }

        GreeterState.currentSessionIndex = 0;
        GreeterState.selectedSession = GreeterState.sessionExecs[0] || "";
        GreeterState.selectedSessionPath = GreeterState.sessionPaths[0] || "";
        GreeterState.selectedSessionDesktopId = GreeterState.sessionDesktopIds[0] || "";
        GreeterState.selectedSessionDesktopNames = GreeterState.sessionDesktopNames[0] || "";
    }

    property var sessionDirs: {
        const homeDir = Quickshell.env("HOME") || "";
        const dirs = ["/usr/share/wayland-sessions", "/usr/share/xsessions", "/usr/local/share/wayland-sessions", "/usr/local/share/xsessions"];

        if (homeDir) {
            dirs.push(homeDir + "/.local/share/wayland-sessions");
            dirs.push(homeDir + "/.local/share/xsessions");
        }

        if (xdgDataDirs) {
            xdgDataDirs.split(":").forEach(dir => {
                if (dir) {
                    dirs.push(dir + "/wayland-sessions");
                    dirs.push(dir + "/xsessions");
                }
            });
        }

        // _addSession guards against a session name already existing
        // so we have to load from the user directories first so they
        // correctly override a system configuration
        return dirs.reverse();
    }

    property var _pendingFiles: ({})
    property int _pendingCount: 0

    function _addSession(path, name, exec, desktopNames) {
        if (!name || !exec || GreeterState.sessionList.includes(name))
            return;
        GreeterState.sessionList = GreeterState.sessionList.concat([name]);
        GreeterState.sessionExecs = GreeterState.sessionExecs.concat([exec]);
        GreeterState.sessionPaths = GreeterState.sessionPaths.concat([path]);
        GreeterState.sessionDesktopIds = GreeterState.sessionDesktopIds.concat([desktopIdFromPath(path)]);
        GreeterState.sessionDesktopNames = GreeterState.sessionDesktopNames.concat([desktopNames]);
    }

    function _parseDesktopFile(content, path) {
        let name = "";
        let exec = "";
        let desktopNames = "";
        const lines = content.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!name && line.startsWith("Name="))
                name = line.substring(5).trim();
            else if (!exec && line.startsWith("Exec="))
                exec = line.substring(5).trim();
            else if (!desktopNames && line.startsWith("DesktopNames="))
                desktopNames = line.substring(13).trim();
        }
        _addSession(path, name, exec, desktopNames);
    }

    function sessionLaunchEnv(sessionDesktopId, desktopNames) {
        const env = ["XDG_SESSION_TYPE=wayland"];
        const desktopSession = (sessionDesktopId || "").replace(/\.desktop$/, "");
        if (desktopSession)
            env.push("XDG_SESSION_DESKTOP=" + desktopSession, "DESKTOP_SESSION=" + desktopSession);
        const currentDesktop = (desktopNames || "").replace(/;/g, ":").replace(/^:+|:+$/g, "");
        if (currentDesktop)
            env.push("XDG_CURRENT_DESKTOP=" + currentDesktop);
        return env;
    }

    function _loadDesktopFile(filePath) {
        if (_pendingFiles[filePath])
            return;
        _pendingFiles[filePath] = true;
        _pendingCount++;

        const loader = desktopFileLoader.createObject(root, {
            "filePath": filePath
        });
    }

    function _onFileLoaded(filePath) {
        _pendingCount--;
        if (_pendingCount === 0)
            Qt.callLater(finalizeSessionSelection);
    }

    Component {
        id: desktopFileLoader

        FileView {
            id: fv
            property string filePath: ""
            path: filePath

            onLoaded: {
                root._parseDesktopFile(text(), filePath);
                root._onFileLoaded(filePath);
                fv.destroy();
            }

            onLoadFailed: {
                root._onFileLoaded(filePath);
                fv.destroy();
            }
        }
    }

    Repeater {
        model: isPrimaryScreen ? sessionDirs : []

        Item {
            required property string modelData

            FolderListModel {
                folder: encodeFileUrl(modelData)
                nameFilters: ["*.desktop"]
                showDirs: false
                showDotAndDotDot: false

                onStatusChanged: {
                    if (status !== FolderListModel.Ready)
                        return;
                    for (let i = 0; i < count; i++) {
                        let fp = get(i, "filePath");
                        if (fp.startsWith("file://"))
                            fp = fp.substring(7);
                        root._loadDesktopFile(fp);
                    }
                }
            }
        }
    }

    Connections {
        target: Greetd
        enabled: isPrimaryScreen

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                awaitingExternalAuth = false;
                pendingPasswordResponse = true;
                const hasPasswordBuffer = GreeterState.passwordBuffer && GreeterState.passwordBuffer.length > 0;
                if (!passwordSubmitRequested && hasPasswordBuffer)
                    passwordSubmitRequested = true;
                if (passwordSubmitRequested && !root.submitBufferedPassword())
                    passwordSubmitRequested = false;
                if (passwordSubmitRequested || hasPasswordBuffer) {
                    authTimeout.interval = defaultAuthTimeoutMs;
                    authTimeout.restart();
                } else {
                    authTimeout.stop();
                }
                return;
            }
            pendingPasswordResponse = false;
            if (!passwordSubmitRequested)
                awaitingExternalAuth = root.greeterExternalAuthAvailable;
            if (awaitingExternalAuth || (passwordSubmitRequested && root.greeterPamHasExternalAuth))
                authTimeout.interval = externalAuthTimeoutMs;
            else
                authTimeout.interval = defaultAuthTimeoutMs;
            authTimeout.restart();
            Greetd.respond("");
        }

        function onStateChanged() {
            if (Greetd.state === GreetdState.Inactive) {
                awaitingExternalAuth = false;
                pendingPasswordResponse = false;
                authTimeout.interval = defaultAuthTimeoutMs;
                authTimeout.stop();
                passwordSubmitRequested = false;
            }
        }

        function onReadyToLaunch() {
            awaitingExternalAuth = false;
            pendingPasswordResponse = false;
            passwordSubmitRequested = false;
            authTimeout.interval = defaultAuthTimeoutMs;
            authTimeout.stop();
            passwordFailureCount = 0;
            clearAuthFeedback();
            const sessionCmd = GreeterState.selectedSession || GreeterState.sessionExecs[GreeterState.currentSessionIndex];
            const sessionPath = GreeterState.selectedSessionPath || GreeterState.sessionPaths[GreeterState.currentSessionIndex];
            const sessionDesktopId = GreeterState.selectedSessionDesktopId || GreeterState.sessionDesktopIds[GreeterState.currentSessionIndex] || desktopIdFromPath(sessionPath);
            const sessionDesktopNames = GreeterState.selectedSessionDesktopNames || GreeterState.sessionDesktopNames[GreeterState.currentSessionIndex] || "";
            if (!sessionCmd) {
                GreeterState.pamState = "error";
                authFeedbackMessage = currentAuthMessage();
                placeholderDelay.restart();
                return;
            }

            GreeterState.unlocking = true;
            launchTimeout.restart();
            if (GreetdSettings.rememberLastSession) {
                GreetdMemory.setLastSession(sessionPath, sessionDesktopId);
            } else if (GreetdMemory.lastSessionId || GreetdMemory.lastSessionDesktopId) {
                GreetdMemory.setLastSession("", "");
            }
            if (GreetdSettings.rememberLastUser) {
                GreetdMemory.setLastSuccessfulUser(GreeterState.username);
            } else if (GreetdMemory.lastSuccessfulUser) {
                GreetdMemory.setLastSuccessfulUser("");
            }
            if (root.autoLoginOnSuccess)
                greeterAutoLoginPendingProcess.running = true;
            pendingLaunchCommand = sessionCmd;
            pendingLaunchEnv = sessionLaunchEnv(sessionDesktopId, sessionDesktopNames).concat(["DMS_GREETER_AUTH_TIME=" + Math.floor(Date.now() / 1000)]);
            if (Quickshell.env("DMS_VOID") === "1")
                pendingLaunchEnv.push("LIBSEAT_BACKEND=logind");
            memoryFlushTimer.restart();
        }

        function onAuthFailure(message) {
            awaitingExternalAuth = false;
            pendingPasswordResponse = false;
            passwordSubmitRequested = false;
            authTimeout.interval = defaultAuthTimeoutMs;
            authTimeout.stop();
            launchTimeout.stop();
            GreeterState.unlocking = false;
            if (isLikelyLockoutMessage(message)) {
                GreeterState.pamState = "max";
            } else {
                GreeterState.pamState = "fail";
                passwordFailureCount = passwordFailureCount + 1;
            }
            authFeedbackMessage = currentAuthMessage();
            GreeterState.passwordBuffer = "";
            root.clearInput();
            placeholderDelay.restart();
            Greetd.cancelSession();
        }

        function onError(error) {
            awaitingExternalAuth = false;
            pendingPasswordResponse = false;
            passwordSubmitRequested = false;
            authTimeout.interval = defaultAuthTimeoutMs;
            authTimeout.stop();
            launchTimeout.stop();
            GreeterState.unlocking = false;
            GreeterState.pamState = "error";
            authFeedbackMessage = currentAuthMessage();
            GreeterState.passwordBuffer = "";
            root.clearInput();
            placeholderDelay.restart();
            Greetd.cancelSession();
        }
    }

    Timer {
        id: memoryFlushTimer
        interval: memoryFlushDelayMs
        onTriggered: {
            if (!pendingLaunchCommand)
                return;
            const sessionCommand = pendingLaunchCommand;
            const launchEnv = pendingLaunchEnv;
            pendingLaunchCommand = "";
            pendingLaunchEnv = [];
            const sessionArgs = sessionCommand.trim().split(/\s+/);
            const needsVoidDbusSession = Quickshell.env("DMS_VOID") === "1" && !Quickshell.env("DBUS_SESSION_BUS_ADDRESS") && sessionArgs[0] !== "dbus-run-session";
            const launchArgs = needsVoidDbusSession ? ["dbus-run-session"].concat(sessionArgs) : sessionArgs;
            Greetd.launch(launchArgs, launchEnv);
        }
    }

    Timer {
        id: authTimeout
        interval: defaultAuthTimeoutMs
        onTriggered: {
            if (GreeterState.unlocking || Greetd.state === GreetdState.Inactive)
                return;
            awaitingExternalAuth = false;
            pendingPasswordResponse = false;
            passwordSubmitRequested = false;
            authTimeout.interval = defaultAuthTimeoutMs;
            GreeterState.pamState = "error";
            authFeedbackMessage = currentAuthMessage();
            GreeterState.passwordBuffer = "";
            root.clearInput();
            placeholderDelay.restart();
            Greetd.cancelSession();
        }
    }

    Timer {
        id: launchTimeout
        interval: 8000
        onTriggered: {
            if (!GreeterState.unlocking)
                return;
            pendingPasswordResponse = false;
            passwordSubmitRequested = false;
            GreeterState.unlocking = false;
            GreeterState.pamState = "error";
            authFeedbackMessage = currentAuthMessage();
            placeholderDelay.restart();
            Greetd.cancelSession();
        }
    }

    Timer {
        id: placeholderDelay
        interval: 4000
        onTriggered: clearAuthFeedback()
    }

    LockPowerMenu {
        id: powerMenu
        expressive: true
        showLogout: false
        powerActionConfirmOverride: SettingsData.powerActionConfirm
        powerActionHoldDurationOverride: SettingsData.powerActionHoldDuration
        powerMenuActionsOverride: SettingsData.powerMenuActions
        powerMenuDefaultActionOverride: SettingsData.powerMenuDefaultAction
        powerMenuGridLayoutOverride: SettingsData.powerMenuGridLayout
        requiredActions: ["poweroff"]
        onClosed: {
            if (isPrimaryScreen)
                Qt.callLater(root.focusInput);
        }
    }
}
