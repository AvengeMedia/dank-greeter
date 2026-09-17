import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool expanded: false
    property int maxExpandedHeight: 400
    property bool autoLoginVisible: false
    property bool autoLoginChecked: false
    property bool manualEntryVisible: false

    signal userSelected(string username)
    signal toggleRequested
    signal autoLoginToggled
    signal manualEntryRequested

    readonly property int rowHeight: Theme.listItemHeight
    readonly property int collapsedBarHeight: Theme.buttonHeightXS
    readonly property int actionRowHeight: Theme.menuItemHeight

    component StateRow: Rectangle {
        id: stateRow

        property bool selected: false
        readonly property color contentColor: selected ? Theme.onSecondaryContainer : Theme.surfaceText
        readonly property color iconColor: selected ? Theme.onSecondaryContainer : Theme.surfaceVariantText
        default property alias content: rowLayout.data

        signal clicked

        width: parent ? parent.width : 0
        radius: rowArea.pressed ? Theme.cornerRadiusS : Theme.fullRadius(width, height)
        color: selected ? Theme.secondaryContainer : Theme.withAlpha(Theme.surfaceText, rowArea.pressed ? Theme.stateLayerPressed : (rowArea.containsMouse ? Theme.stateLayerHover : 0))

        Behavior on radius {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        RowLayout {
            id: rowLayout

            anchors.fill: parent
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM
        }

        MouseArea {
            id: rowArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: stateRow.clicked()
        }
    }

    readonly property int userListFullHeight: {
        const count = GreeterUsersService.users.length;
        if (count === 0)
            return 0;
        return count * rowHeight + Math.max(0, count - 1) * Theme.spacingXS;
    }
    readonly property int manualEntryBlockHeight: manualEntryVisible ? actionRowHeight + Theme.spacingXS : 0
    readonly property int autoLoginBlockHeight: autoLoginVisible ? actionRowHeight + Theme.spacingXS : 0
    readonly property int expandedContentHeight: {
        if (!expanded)
            return 0;
        if (GreeterUsersService.users.length === 0 && !autoLoginVisible && !manualEntryVisible)
            return 0;
        return Math.min(maxExpandedHeight, userListFullHeight + manualEntryBlockHeight + autoLoginBlockHeight);
    }

    function encodeFileUrl(path) {
        if (!path)
            return "";
        return "file://" + path.split("/").map(s => encodeURIComponent(s)).join("/");
    }

    function profileImageSource(username) {
        const path = GreeterUsersService.profileImagePath(username);
        if (path)
            return encodeFileUrl(path);
        return "";
    }

    implicitHeight: expanded ? expandedContentHeight : collapsedBarHeight
    implicitWidth: parent ? parent.width : 320

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: collapsedBarHeight
        visible: !expanded

        RowLayout {
            anchors.fill: parent
            spacing: Theme.spacingM

            StyledText {
                Layout.fillWidth: true
                text: GreeterState.username ? GreeterUsersService.optionLabel(GreeterState.username) : I18n.tr("Select user...", "greeter user picker placeholder")
                color: GreeterState.username ? Theme.surfaceText : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
            }

            DankIcon {
                Layout.alignment: Qt.AlignVCenter
                name: "expand_more"
                size: Theme.iconSizeMedium
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleRequested()
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.expandedContentHeight
        visible: expanded
        spacing: Theme.spacingXS

        DankListView {
            id: userListView

            width: parent.width
            height: parent.height - root.manualEntryBlockHeight - root.autoLoginBlockHeight
            clip: true
            interactive: contentHeight > height
            spacing: Theme.spacingXS
            model: GreeterUsersService.users

            delegate: StateRow {
                id: userRow

                required property var modelData
                required property int index

                width: userListView.width
                height: root.rowHeight
                selected: GreeterState.username === modelData.username
                onClicked: root.userSelected(modelData.username)

                DankCircularImage {
                    Layout.preferredWidth: Theme.avatarSize
                    Layout.preferredHeight: Theme.avatarSize
                    imageSource: root.profileImageSource(userRow.modelData.username)
                    fallbackIcon: "material:person"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: GreeterUsersService.optionLabel(userRow.modelData.username)
                    color: userRow.contentColor
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                }
            }
        }

        StateRow {
            height: root.actionRowHeight
            visible: root.manualEntryVisible
            onClicked: root.manualEntryRequested()

            DankIcon {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Theme.spacingS
                name: "person_add"
                size: Theme.iconSizeMedium
                color: Theme.surfaceVariantText
            }

            StyledText {
                Layout.fillWidth: true
                text: I18n.tr("Not listed?", "greeter link to switch to manual username entry")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
            }
        }

        StateRow {
            height: root.actionRowHeight
            visible: root.autoLoginVisible
            onClicked: root.autoLoginToggled()

            DankIcon {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Theme.spacingS
                name: root.autoLoginChecked ? "check_box" : "check_box_outline_blank"
                size: Theme.iconSizeMedium
                color: root.autoLoginChecked ? Theme.primary : Theme.surfaceVariantText
            }

            StyledText {
                Layout.fillWidth: true
                text: I18n.tr("Auto-login")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
            }
        }
    }
}
