pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Greetd
import qs.Common
import qs.Services
import qs.Widgets
import qs.DankCommon.Session

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var host: lockHost
    readonly property var cfg: instanceData?.config ?? ({})
    // Ring cannot host the user picker, so the greeter renders it as the pill.
    readonly property string style: cfg.style === "ring" ? "pill" : (cfg.style ?? "pill")
    readonly property bool pickerPhase: host?.showUserPicker ?? false
    readonly property bool contained: pickerPhase || style === "pill" || style === "expressive"
    readonly property bool dots: !pickerPhase && style === "dots"
    readonly property bool morph: !pickerPhase && style === "expressive"
    readonly property bool minimal: !pickerPhase && style === "minimal"
    readonly property string profileVisibility: cfg.profileVisibility ?? (cfg.showProfileImage === false ? "never" : "always")
    readonly property string passwordVisibility: cfg.passwordVisibility ?? (cfg.showPasswordField === false ? "typing" : "always")
    readonly property bool authenticating: Greetd.state !== GreetdState.Inactive && !(host?.awaitingExternalAuth ?? false) && !(host?.pendingPasswordResponse ?? false)
    readonly property bool failed: GreeterState.pamState !== ""
    readonly property bool inputVisible: !GreeterState.showPasswordInput || passwordVisibility !== "typing" || GreeterState.passwordBuffer.length > 0 || authenticating || GreeterState.unlocking || failed
    readonly property bool pickerAvailable: host?.pickerAvailable ?? false
    // The synced visibility wins; with the avatar hidden, Escape on an empty password returns to the user list.
    readonly property bool showProfileImage: profileVisibility === "always" || (profileVisibility === "typing" && GreeterState.showPasswordInput && inputVisible)
    readonly property var morphShapes: ["cookie4", "clover4", "sunny", "cookie9", "softBurst", "pentagon", "oval", "cookie6"]
    readonly property string morphShape: morphShapes[GreeterState.passwordBuffer.length % morphShapes.length]
    readonly property color accentColor: Theme.primary
    readonly property color plainColor: Theme.lockScreenContentColor
    readonly property Item inputItem: inputField
    readonly property real minWidth: LockMetrics.fieldWidth / 2
    readonly property real minHeight: implicitHeight
    readonly property bool resizable: true
    property int typedCount: 0

    implicitWidth: Math.min(LockMetrics.passwordRowWidth, (host?.width ?? LockMetrics.passwordRowWidth) - Theme.spacingXL * 2)
    implicitHeight: authColumn.implicitHeight

    function clearInput() {
        inputField.syncingFromState = true;
        inputField.text = "";
        inputField.syncingFromState = false;
    }

    function focusInput() {
        inputField.forceActiveFocus();
    }

    onLockHostChanged: {
        if (!lockHost)
            return;
        lockHost.authWidget = root;
        if (lockHost.isPrimaryScreen && !lockHost.powerMenuVisible)
            inputField.forceActiveFocus();
    }

    Component.onDestruction: {
        if (lockHost && lockHost.authWidget === root)
            lockHost.authWidget = null;
    }

    Connections {
        target: GreeterState

        function onPamStateChanged() {
            if (GreeterState.pamState !== "")
                errorShake.restart();
        }

        function onPasswordBufferChanged() {
            const grew = GreeterState.passwordBuffer.length > root.typedCount;
            root.typedCount = GreeterState.passwordBuffer.length;
            if (grew)
                morphPulse.restart();
        }
    }

    ColumnLayout {
        id: authColumn

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacingM

        RowLayout {
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            spacing: Theme.spacingM
            Layout.fillWidth: true

            Item {
                Layout.preferredWidth: LockMetrics.avatarSize
                Layout.preferredHeight: LockMetrics.avatarSize
                Layout.alignment: Qt.AlignTop
                visible: root.showProfileImage

                DankCircularImage {
                    anchors.fill: parent
                    imageSource: {
                        const displayUser = GreeterState.username || (root.host?.pickerThemeUsername ?? "");
                        if (!displayUser)
                            return "";
                        const cachedPath = GreeterUsersService.profileImagePath(displayUser);
                        return cachedPath ? root.host.encodeFileUrl(cachedPath) : "";
                    }
                    fallbackIcon: "material:person"
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.fullRadius(width, height)
                    color: "transparent"
                    border.color: Theme.focusRingColor
                    border.width: (avatarPickerArea.containsMouse || (root.host?.userListOpen ?? false)) && !GreeterState.showPasswordInput ? Theme.focusRingWidth : 0
                    visible: root.pickerAvailable
                    Behavior on border.width {
                        NumberAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.fullRadius(width, height)
                    color: Theme.withAlpha(Theme.scrimColor, Theme.scrimAlpha)
                    opacity: ((root.host?.pickerAvailable ?? false) && GreeterState.showPasswordInput && avatarPickerArea.containsMouse) ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: "switch_account"
                        size: Theme.iconSize
                        color: Theme.lockScreenContentColor
                    }
                }

                MouseArea {
                    id: avatarPickerArea

                    anchors.fill: parent
                    visible: root.host?.pickerAvailable ?? false
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (GreeterState.showPasswordInput)
                            root.host.returnToUserPicker();
                        else if (root.host.manualUsernameEntry)
                            root.host.returnToUserListFromManualEntry();
                        else
                            root.host.userListOpen = !root.host.userListOpen;
                    }
                }
            }

            Rectangle {
                id: passwordBox

                property bool showPassword: false
                property real errorOffset: 0

                transform: Translate {
                    x: Math.max(-LockMetrics.shakeDistance, Math.min(LockMetrics.shakeDistance, passwordBox.errorOffset))
                }

                Layout.fillWidth: true
                Layout.preferredHeight: root.pickerPhase && (root.host?.userListOpen ?? false) ? Math.max(LockMetrics.fieldHeight, userPicker.implicitHeight + Theme.spacingM * 2) : LockMetrics.fieldHeight

                clip: true
                opacity: root.inputVisible ? 1 : 0
                radius: root.morph ? Theme.cornerRadiusXL : Theme.fullRadius(width, LockMetrics.fieldHeight)
                color: {
                    if (!root.contained)
                        return "transparent";
                    return root.morph ? Theme.surfaceContainerHigh : Theme.cardSurface;
                }
                border.width: {
                    if (!root.contained)
                        return 0;
                    return inputField.activeFocus ? Math.max(Theme.outlineWidth, Theme.focusRingWidth) : Theme.layerOutlineWidth;
                }
                border.color: inputField.activeFocus ? Theme.focusRingColor : Theme.outlineMedium

                Behavior on opacity {
                    NumberAnimation {
                        duration: LockMetrics.effectsDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: root.minimal
                    height: inputField.activeFocus ? Theme.outlineWidthFocused : Theme.dividerWidth
                    color: {
                        if (root.failed)
                            return Theme.error;
                        return inputField.activeFocus ? root.accentColor : Theme.withAlpha(root.plainColor, Theme.pendingOpacity);
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                GreeterUserPicker {
                    id: userPicker

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: (root.host?.userListOpen ?? false) ? undefined : parent.verticalCenter
                    anchors.top: (root.host?.userListOpen ?? false) ? parent.top : undefined
                    anchors.margins: Theme.spacingM
                    maxExpandedHeight: root.host?.userPickerMaxHeight ?? 400
                    visible: root.pickerPhase && !GreeterState.showPasswordInput
                    expanded: root.host?.userListOpen ?? false
                    autoLoginVisible: root.host?.autoLoginAvailable ?? false
                    autoLoginChecked: root.host?.autoLoginOnSuccess ?? false
                    manualEntryVisible: true
                    onUserSelected: username => root.host.selectUser(username)
                    onToggleRequested: root.host.userListOpen = !root.host.userListOpen
                    onAutoLoginToggled: root.host.autoLoginOnSuccess = !root.host.autoLoginOnSuccess
                    onManualEntryRequested: root.host.enterManualUsernameEntry()
                }

                Item {
                    id: lockIconContainer
                    anchors.left: parent.left
                    anchors.leftMargin: root.morph ? Theme.spacingS : Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.pickerPhase && !root.dots && !root.minimal
                    width: !visible ? 0 : (root.morph ? LockMetrics.fieldHeight - Theme.spacingS * 2 : Theme.iconSizeSmall)
                    height: root.morph ? width : Theme.iconSizeSmall

                    DankMaterialShape {
                        id: morphContainer
                        anchors.fill: parent
                        visible: root.morph
                        shape: root.morphShape
                        color: root.failed ? Theme.errorContainer : Theme.primaryContainer

                        SequentialAnimation {
                            id: morphPulse
                            NumberAnimation {
                                target: morphContainer
                                property: "scale"
                                to: 1.15
                                duration: LockMetrics.shakeDuration / 2
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                            }
                            NumberAnimation {
                                target: morphContainer
                                property: "scale"
                                to: 1
                                duration: LockMetrics.shakeDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: LockMetrics.effectsDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }

                    DankLoadingIndicator {
                        anchors.centerIn: parent
                        size: parent.width
                        contained: true
                        visible: root.morph && root.authenticating
                        running: visible
                    }

                    DankIcon {
                        id: lockIcon
                        anchors.centerIn: parent
                        visible: !(root.morph && root.authenticating)
                        name: GreeterState.showPasswordInput ? "lock" : "person"
                        size: Theme.iconSizeSmall
                        color: {
                            if (root.morph)
                                return root.failed ? Theme.onErrorContainer : Theme.onPrimaryContainer;
                            if (inputField.activeFocus)
                                return root.accentColor;
                            return root.contained ? Theme.surfaceVariantText : Theme.withAlpha(root.plainColor, Theme.pendingOpacity);
                        }
                    }
                }

                TextInput {
                    id: inputField

                    property bool syncingFromState: false

                    anchors.fill: parent
                    anchors.leftMargin: lockIconContainer.width + Theme.spacingM * 2
                    anchors.rightMargin: {
                        let margin = Theme.spacingM;
                        if (GreeterState.showPasswordInput && revealButton.visible)
                            margin += revealButton.width;
                        if (externalAuthButton.visible)
                            margin += externalAuthButton.width;
                        if (virtualKeyboardButton.visible)
                            margin += virtualKeyboardButton.width;
                        if (enterButton.visible)
                            margin += enterButton.width + Theme.spacingXXS;
                        return margin;
                    }
                    enabled: !root.pickerPhase || GreeterState.showPasswordInput
                    opacity: 0
                    focus: !root.pickerPhase || GreeterState.showPasswordInput
                    echoMode: GreeterState.showPasswordInput ? (passwordBox.showPassword ? TextInput.Normal : TextInput.Password) : TextInput.Normal
                    KeyNavigation.tab: virtualKeyboardButton.visible ? virtualKeyboardButton : (root.host?.sessionDropdownItem ?? inputField)
                    KeyNavigation.backtab: root.host?.sessionDropdownItem ?? inputField

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab && GreeterState.showPasswordInput && (!text || text.length === 0) && !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && root.host.greeterExternalAuthAvailable && !root.host.externalAuthInProgress && !root.host.pendingPasswordResponse && Greetd.state === GreetdState.Inactive && !GreeterState.unlocking) {
                            root.host.startAuthSession(false);
                            event.accepted = true;
                            return;
                        }
                        if (event.key !== Qt.Key_Escape || !GreeterState.showPasswordInput)
                            return;
                        if (text.length > 0) {
                            root.clearInput();
                            GreeterState.passwordBuffer = "";
                            event.accepted = true;
                            return;
                        }
                        if (root.pickerAvailable && !GreeterState.unlocking) {
                            root.host.returnToUserPicker();
                            event.accepted = true;
                        }
                    }

                    // Contract the on-screen Keyboard drives its target through.
                    function insertText(value) {
                        if (value)
                            insert(cursorPosition, value);
                    }

                    function backspace() {
                        if (cursorPosition > 0)
                            remove(cursorPosition - 1, cursorPosition);
                    }

                    onTextChanged: {
                        if (syncingFromState)
                            return;
                        if (GreeterState.showPasswordInput) {
                            GreeterState.passwordBuffer = text;
                            if (!text || text.length === 0)
                                root.host.passwordSubmitRequested = false;
                        } else {
                            GreeterState.usernameInput = text;
                        }
                    }
                    onAccepted: {
                        if (GreeterState.showPasswordInput) {
                            root.host.startAuthSession(true);
                            return;
                        }
                        if (!text.trim())
                            return;
                        root.host.submitUsername(text);
                        root.clearInput();
                    }

                    Component.onCompleted: {
                        syncingFromState = true;
                        text = GreeterState.showPasswordInput ? GreeterState.passwordBuffer : GreeterState.usernameInput;
                        syncingFromState = false;
                    }
                    onVisibleChanged: {
                        if (visible && root.host?.isPrimaryScreen && !root.host.powerMenuVisible)
                            forceActiveFocus();
                    }
                }

                KeyboardController {
                    id: keyboardController
                    target: inputField
                    rootObject: root.host
                    expressive: true
                }

                StyledText {
                    id: placeholder

                    anchors.left: lockIconContainer.right
                    anchors.leftMargin: root.minimal ? 0 : Theme.spacingM
                    anchors.right: (GreeterState.showPasswordInput && revealButton.visible ? revealButton.left : (externalAuthButton.visible ? externalAuthButton.left : (virtualKeyboardButton.visible ? virtualKeyboardButton.left : (enterButton.visible ? enterButton.left : parent.right))))
                    anchors.rightMargin: Theme.spacingXXS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.dots
                    text: {
                        if (GreeterState.unlocking)
                            return I18n.tr("Logging in...");
                        if (root.authenticating)
                            return I18n.tr("Authenticating...");
                        if (GreeterState.showPasswordInput)
                            return root.passwordVisibility === "always" ? I18n.tr("Password...") : "";
                        if (root.pickerPhase)
                            return "";
                        return I18n.tr("Username...");
                    }
                    color: {
                        if (GreeterState.unlocking || root.authenticating)
                            return root.accentColor;
                        return root.contained ? Theme.outline : Theme.withAlpha(root.plainColor, Theme.pendingOpacity);
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    opacity: (GreeterState.showPasswordInput ? GreeterState.passwordBuffer.length === 0 : (root.pickerPhase ? false : GreeterState.usernameInput.length === 0)) ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Item {
                    id: textViewport
                    anchors.left: lockIconContainer.right
                    anchors.leftMargin: root.minimal ? 0 : Theme.spacingM
                    anchors.right: placeholder.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    clip: true
                    visible: !root.dots || passwordBox.showPassword || !GreeterState.showPasswordInput

                    StyledText {
                        id: echoText
                        x: Math.min(0, textViewport.width - implicitWidth)
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!GreeterState.showPasswordInput)
                                return GreeterState.usernameInput;
                            return passwordBox.showPassword ? GreeterState.passwordBuffer : "•".repeat(GreeterState.passwordBuffer.length);
                        }
                        color: root.contained ? Theme.surfaceText : root.plainColor
                        font.pixelSize: (GreeterState.showPasswordInput && !passwordBox.showPassword) ? (root.contained ? Theme.fontSizeLarge : Theme.fontSizeXLarge) : Theme.fontSizeMedium
                        opacity: (GreeterState.showPasswordInput ? GreeterState.passwordBuffer.length > 0 : (root.pickerPhase ? false : GreeterState.usernameInput.length > 0)) ? 1 : 0
                        wrapMode: Text.NoWrap
                        elide: Text.ElideNone

                        Behavior on opacity {
                            NumberAnimation {
                                duration: LockMetrics.effectsDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }
                }

                Item {
                    id: dotViewport
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: placeholder.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    clip: true
                    visible: root.dots && GreeterState.showPasswordInput && !passwordBox.showPassword

                    Row {
                        x: Math.min(0, dotViewport.width - width)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        Repeater {
                            model: Math.max(1, GreeterState.passwordBuffer.length)

                            Rectangle {
                                required property int index
                                readonly property bool filled: index < GreeterState.passwordBuffer.length
                                readonly property color tone: root.failed ? Theme.error : root.accentColor

                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.iconSizeSmall
                                height: width
                                radius: Theme.fullRadius(width, height)
                                color: filled ? tone : "transparent"
                                border.width: Theme.outlineWidthFocused
                                border.color: filled ? tone : Theme.withAlpha(root.plainColor, Theme.pendingOpacity)
                                scale: filled ? 1 : 0.8

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: LockMetrics.shakeDuration
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                                    }
                                }
                            }
                        }
                    }
                }

                LockActionButton {
                    id: revealButton

                    activeFocusOnTab: false
                    Accessible.name: passwordBox.showPassword ? I18n.tr("Hide password") : I18n.tr("Show password")

                    anchors.right: externalAuthButton.visible ? externalAuthButton.left : (virtualKeyboardButton.visible ? virtualKeyboardButton.left : (enterButton.visible ? enterButton.left : parent.right))
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: passwordBox.showPassword ? "visibility_off" : "visibility"
                    buttonSize: Theme.buttonHeightXS
                    visible: !root.minimal && GreeterState.showPasswordInput && GreeterState.passwordBuffer.length > 0 && !root.authenticating && !GreeterState.unlocking
                    enabled: visible
                    onClicked: passwordBox.showPassword = !passwordBox.showPassword
                }

                LockActionButton {
                    id: externalAuthButton

                    activeFocusOnTab: false
                    tooltipText: root.host?.greeterPamHasFprint ? I18n.tr("Fingerprint") : (root.host?.greeterPamHasFaceAuth ? I18n.tr("Face recognition") : I18n.tr("Security key"))

                    anchors.right: virtualKeyboardButton.visible ? virtualKeyboardButton.left : (enterButton.visible ? enterButton.left : parent.right)
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: root.host?.greeterPamHasFprint ? "fingerprint" : (root.host?.greeterPamHasFaceAuth ? "face" : "key")
                    buttonSize: Theme.buttonHeightXS
                    visible: GreeterState.showPasswordInput && (root.host?.greeterExternalAuthAvailable ?? false) && GreeterState.passwordBuffer.length === 0 && !root.authenticating && !GreeterState.unlocking
                    enabled: visible
                    onClicked: root.host.startAuthSession(false)
                }

                LockActionButton {
                    id: virtualKeyboardButton

                    Accessible.name: I18n.tr("Keyboard")
                    KeyNavigation.tab: root.host?.sessionDropdownItem ?? inputField
                    KeyNavigation.backtab: inputField
                    Keys.onEscapePressed: {
                        keyboardController.hide();
                        inputField.forceActiveFocus();
                    }

                    anchors.right: enterButton.visible ? enterButton.left : parent.right
                    anchors.rightMargin: enterButton.visible ? 0 : Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "keyboard"
                    buttonSize: Theme.buttonHeightXS
                    visible: !root.minimal && !root.authenticating && !GreeterState.unlocking && (!root.pickerPhase || GreeterState.showPasswordInput)
                    enabled: visible
                    onClicked: {
                        if (keyboardController.isKeyboardActive)
                            keyboardController.hide();
                        else
                            keyboardController.show();
                    }
                }

                DankLoadingIndicator {
                    anchors.right: enterButton.visible ? enterButton.left : parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.iconSize
                    color: root.accentColor
                    visible: !root.morph && root.authenticating && !GreeterState.unlocking
                    running: visible
                }

                LockActionButton {
                    id: enterButton

                    activeFocusOnTab: false
                    Accessible.name: I18n.tr("Login")

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXXS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "keyboard_return"
                    buttonSize: Theme.buttonHeightXS
                    visible: !root.minimal && !root.authenticating && !GreeterState.unlocking && (!root.pickerPhase || GreeterState.showPasswordInput)
                    onClicked: {
                        if (GreeterState.showPasswordInput) {
                            root.host.startAuthSession(true);
                            return;
                        }
                        if (!inputField.text.trim())
                            return;
                        root.host.submitUsername(inputField.text);
                        root.clearInput();
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: LockMetrics.effectsDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: LockMetrics.effectsDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: (root.host?.showAccountSwitchLink ?? false) ? Theme.buttonHeightXS : 0
            visible: root.host?.showAccountSwitchLink ?? false

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Back to user list", "greeter link to return from manual username entry to user picker")
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                font.underline: accountSwitchMouse.containsMouse
            }

            MouseArea {
                id: accountSwitchMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.host.returnToUserListFromManualEntry()
            }
        }

    }

    // Hangs below the box like the DMS lock widget so a centred box centres the field.
    StyledText {
        anchors.top: authColumn.bottom
        anchors.topMargin: Theme.spacingS
        anchors.left: parent.left
        anchors.right: parent.right
        text: root.host?.authDisplayMessage ?? ""
        color: (root.host?.authFeedbackMessage ?? "") !== "" ? Theme.error : Theme.lockScreenContentColor
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        opacity: text !== "" ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: LockMetrics.effectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    SequentialAnimation {
        id: errorShake

        NumberAnimation {
            target: passwordBox
            property: "errorOffset"
            to: LockMetrics.shakeDistance
            duration: LockMetrics.shakeDuration / 3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: passwordBox
            property: "errorOffset"
            to: -LockMetrics.shakeDistance
            duration: LockMetrics.shakeDuration / 3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: passwordBox
            property: "errorOffset"
            to: 0
            duration: LockMetrics.shakeDuration / 3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }
}
