import QtQuick
import qs.Common

Item {
    id: root

    required property var instanceData
    required property var screen
    required property var hostLayer
    property var lockHost: null

    readonly property string instanceId: instanceData?.id ?? ""
    readonly property string widgetType: instanceData?.widgetType ?? ""
    readonly property bool hasSavedPosition: geometry.hasSavedPosition
    readonly property bool automaticPlacement: widgetType === "lockClock" && (instanceData?.config?.autoPosition ?? true) && !hasSavedPosition
    readonly property var stock: hostLayer.stockRect(widgetType, root)

    x: geometry.widgetX
    y: geometry.widgetY
    width: geometry.widgetWidth
    height: geometry.widgetHeight

    GreeterWidgetGeometry {
        id: geometry
        instanceId: root.instanceId
        instanceData: root.instanceData
        screen: root.screen
        minWidth: content.item?.minWidth ?? 100
        minHeight: content.item?.minHeight ?? 100
        forceSquare: content.item?.forceSquare ?? false
        defaultWidth: content.item?.defaultWidth ?? ((content.item?.implicitWidth ?? 0) > 0 ? content.item.implicitWidth : 280)
        defaultHeight: content.item?.defaultHeight ?? ((content.item?.implicitHeight ?? 0) > 0 ? content.item.implicitHeight : 180)
        defaultX: root.stock ? root.stock.x : screenWidth / 2 - savedWidth / 2
        defaultY: root.stock ? root.stock.y : screenHeight / 2 - savedHeight / 2
    }

    Loader {
        id: content
        anchors.fill: parent
        focus: root.widgetType === "lockAuth"
        sourceComponent: {
            switch (root.widgetType) {
            case "lockClock":
                return clockComponent;
            case "lockDate":
                return dateComponent;
            case "lockAuth":
                return authComponent;
            case "lockStatus":
                return statusComponent;
            case "lockPower":
                return powerComponent;
            }
            return null;
        }
        onLoaded: {
            item.instanceData = Qt.binding(() => root.instanceData);
            item.lockHost = root.lockHost;
        }
    }

    Component {
        id: clockComponent
        GreeterClockWidget {}
    }

    Component {
        id: dateComponent
        GreeterDateWidget {}
    }

    Component {
        id: authComponent
        GreeterAuthWidget {}
    }

    Component {
        id: statusComponent
        GreeterStatusWidget {}
    }

    Component {
        id: powerComponent
        GreeterPowerWidget {}
    }
}
