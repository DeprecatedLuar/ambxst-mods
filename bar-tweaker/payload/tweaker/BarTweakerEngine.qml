import QtQuick
import QtQuick.Layouts

// BarTweakerEngine: renders BarTweaks.vertical inside the vertical bar.
//
// Single responsibility: turn the resolved model into widgets. It does not
// parse config (BarTweaks) and does not build widgets itself (BarWidgetMap)
// - it only dispatches proxy wiring and seam radii, and lays the three
// groups out.
ColumnLayout {
    id: root

    // Vanilla BarContent.qml's `root` (screen, pinned, radii, shadows) and
    // its `bar` Item (used by the center-centering math below). Neither
    // type is expressible as a formal QML type - both come from the host
    // that instantiates this engine.
    required property var barRoot
    required property var barItem

    spacing: 4

    // ------------------------------------------------------------------
    // Per-id proxy-property dispatch tables. Consulted by wireWidget()
    // below. An id absent from a table simply skips that wiring step - no
    // magic string comparisons scattered through the layout code.
    // ------------------------------------------------------------------
    readonly property var idsUsingEnableShadow: ["launcher", "systray", "tools", "presets", "pin", "power"]
    readonly property var idsUsingLayerEnabled: ["layoutSelector", "controls", "battery", "clock"]
    readonly property var idsNeedingBarRef: ["systray", "layoutSelector", "controls", "battery", "clock"]
    readonly property var idsNeedingScreen: ["workspaces"]

    // Wires the per-id proxy properties BarWidgetMap could not supply
    // itself (it has no reference to barRoot), plus the seam radii derived
    // from the widget's position in its pill. Shared by all three Repeaters
    // so the dispatch logic exists in exactly one place.
    function wireWidget(loader, modelData) {
        const item = loader.item;
        if (!item) {
            console.warn("BarTweakerEngine: '" + modelData.id + "' produced no item, skipping");
            return;
        }

        // Proxy properties first: SysTray/ControlsButton/BatteryIndicator/
        // Clock/LayoutSelectorButton derive their own `vertical` (and thus
        // their own Layout.* hints, read below) from `bar.orientation`, so
        // `barRef` must land before those hints are read.
        if (root.idsNeedingBarRef.indexOf(modelData.id) !== -1) {
            item.barRef = root.barRoot;
        }
        if (root.idsNeedingScreen.indexOf(modelData.id) !== -1) {
            item.screen = root.barRoot.screen;
        }
        if (modelData.id === "pin") {
            item.toggleHandler = function () {
                root.barRoot.pinned = !root.barRoot.pinned;
            };
            item.pinned = Qt.binding(function () {
                return root.barRoot.pinned;
            });
        }

        item.startRadius = Qt.binding(function () {
            return modelData.first ? root.barRoot.outerRadius : root.barRoot.innerRadius;
        });
        item.endRadius = Qt.binding(function () {
            return root.resolveEndRadius(modelData);
        });

        if (root.idsUsingEnableShadow.indexOf(modelData.id) !== -1) {
            item.enableShadow = Qt.binding(function () {
                return root.barRoot.shadowsEnabled;
            });
        }
        if (root.idsUsingLayerEnabled.indexOf(modelData.id) !== -1) {
            item.layerEnabled = Qt.binding(function () {
                return root.barRoot.shadowsEnabled;
            });
        }

        // SysTray/ControlsButton/BatteryIndicator/Clock set their own
        // Layout.* attached properties internally; those go inert once the
        // widget is a grandchild (via Loader) rather than a direct child of
        // the ColumnLayout. Forward the widget's own hints onto the Loader
        // (the actual direct child) as live bindings - SysTray's hints in
        // particular keep changing as tray items load asynchronously.
        loader.Layout.fillWidth = Qt.binding(function () {
            return item.Layout.fillWidth;
        });
        loader.Layout.preferredWidth = Qt.binding(function () {
            return item.Layout.preferredWidth;
        });
        loader.Layout.preferredHeight = Qt.binding(function () {
            return item.Layout.preferredHeight;
        });
    }

    function resolveEndRadius(modelData) {
        return modelData.last ? root.barRoot.outerRadius : root.barRoot.innerRadius;
    }

    Repeater {
        model: BarTweaks.vertical.start
        delegate: Loader {
            id: startLoader
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: BarWidgetMap.componentFor(modelData.id)
            onLoaded: root.wireWidget(startLoader, modelData)
        }
    }

    // Center Group Container
    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter

            // Calculate target position to be absolutely centered in the bar (vertically)
            property real targetY: {
                if (!parent || !root.barItem)
                    return 0;

                // Force re-evaluation when parent moves
                var _trigger = parent.y;

                var parentPos = parent.mapToItem(root.barItem, 0, 0);
                return (root.barItem.height - height) / 2 - parentPos.y;
            }

            // Clamp y position
            y: Math.max(0, Math.min(parent.height - height, targetY))

            height: Math.min(parent.height, implicitHeight)
            width: parent.width
            spacing: 4

            Repeater {
                model: BarTweaks.vertical.center
                delegate: Loader {
                    id: centerLoader
                    Layout.alignment: Qt.AlignHCenter
                    sourceComponent: BarWidgetMap.componentFor(modelData.id)
                    onLoaded: root.wireWidget(centerLoader, modelData)
                }
            }
        }
    }

    Repeater {
        model: BarTweaks.vertical.end
        delegate: Loader {
            id: endLoader
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: BarWidgetMap.componentFor(modelData.id)
            onLoaded: root.wireWidget(endLoader, modelData)
        }
    }
}
