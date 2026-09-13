import QtQuick
import QtQuick.Controls
import qs.modules.components
import qs.modules.theme
import qs.config

Button {
    id: root

    property real startRadius: 0
    property real endRadius: 0
    property bool vertical: false
    property bool enableShadow: true
    property bool pinned: false

    required property var onToggle

    implicitWidth: 36
    implicitHeight: 36

    background: StyledRect {
        id: pinButtonBg
        variant: root.pinned ? "primary" : "bg"
        enableShadow: root.enableShadow

        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.pinned ? 0 : (root.pressed ? 0.5 : (root.hovered ? 0.25 : 0))
            radius: (parent.radius !== undefined ? parent.radius : 0)

            Behavior on opacity {
                enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                NumberAnimation {
                    duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                }
            }
        }
    }

    contentItem: Text {
        text: Icons.pin
        font.family: Icons.font
        font.pixelSize: 18
        color: root.pinned ? pinButtonBg.item : (root.pressed ? Colors.background : (Styling.srItem("overprimary") || Colors.foreground))
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        rotation: root.pinned ? 0 : 45
        Behavior on rotation {
            enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
            NumberAnimation {
                duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
            }
        }

        Behavior on color {
            enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
            ColorAnimation {
                duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
            }
        }
    }

    onClicked: root.onToggle()

    StyledToolTip {
        show: root.hovered
        tooltipText: root.pinned ? "Unpin bar" : "Pin bar"
    }
}
