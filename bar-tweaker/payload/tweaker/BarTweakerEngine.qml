import QtQuick
import QtQuick.Layouts

// BarTweakerEngine: renders the orientation-matched LayoutConfigFile's
// layout inside the bar, laid out along whichever axis the host bar is on.
//
// Single responsibility: turn the resolved model into widgets. It does not
// parse config (BarTweaks) and does not build widgets itself (BarWidgetMap)
// - it only dispatches proxy wiring and seam radii, and lays the three
// groups out.
GridLayout {
    id: root

    // Vanilla BarContent.qml's `root` (screen, pinned, radii, shadows) and
    // its `bar` Item (used by the center-centering math below). Neither
    // type is expressible as a formal QML type - both come from the host
    // that instantiates this engine.
    required property var barRoot
    required property var barItem

    readonly property string verticalOrientation: "vertical"
    readonly property bool vertical: root.barRoot.orientation === root.verticalOrientation

    readonly property var layoutConfig: BarTweaks.byOrientation[root.barRoot.orientation]

    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rowSpacing: 4
    columnSpacing: 4

    // ------------------------------------------------------------------
    // Per-id proxy-property dispatch tables. Consulted by wireWidget()
    // below. An id absent from a table simply skips that wiring step - no
    // magic string comparisons scattered through the layout code.
    // ------------------------------------------------------------------
    readonly property var idsUsingEnableShadow: ["launcher", "systray", "tools", "presets", "pin", "power"]
    readonly property var idsUsingLayerEnabled: ["layoutSelector", "controls", "battery", "clock"]
    readonly property var idsNeedingBarRef: ["systray", "layoutSelector", "controls", "battery", "clock"]
    readonly property var idsNeedingScreen: ["workspaces"]
    readonly property var idsUsingVerticalFlag: ["launcher", "tools", "presets", "power", "pin"]
    readonly property var idsUsingOrientation: ["workspaces"]
    // Widgets whose cross-axis size comes from their literal QML `parent`
    // (e.g. SysTray.qml: `height: vertical ? implicitHeight : parent.height`)
    // rather than from their own Layout.* hints. Once wrapped in this
    // engine's per-widget Loader, `parent` is the Loader, which otherwise has
    // nothing forcing it to the bar's cross-axis size in horizontal mode.
    readonly property var idsNeedingExplicitCrossAxisFill: ["systray"]

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

        if (root.idsUsingVerticalFlag.indexOf(modelData.id) !== -1) {
            item.vertical = Qt.binding(function () {
                return root.vertical;
            });
        }
        if (root.idsUsingOrientation.indexOf(modelData.id) !== -1) {
            item.orientation = Qt.binding(function () {
                return root.barRoot.orientation;
            });
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
        // the layout. Forward the widget's own hints onto the Loader (the
        // actual direct child) as live bindings - SysTray's hints in
        // particular keep changing as tray items load asynchronously.
        loader.Layout.fillWidth = Qt.binding(function () {
            return item.Layout.fillWidth;
        });
        loader.Layout.fillHeight = Qt.binding(function () {
            return item.Layout.fillHeight;
        });
        loader.Layout.preferredWidth = Qt.binding(function () {
            return item.Layout.preferredWidth;
        });
        loader.Layout.preferredHeight = Qt.binding(function () {
            return item.Layout.preferredHeight;
        });
        loader.Layout.maximumWidth = Qt.binding(function () {
            return item.Layout.maximumWidth;
        });
        loader.Layout.maximumHeight = Qt.binding(function () {
            return item.Layout.maximumHeight;
        });

        // Override for widgets that never set Layout.fillHeight themselves
        // (so the generic forward above always yields false) but need the
        // Loader stretched to the bar's cross-axis size in horizontal mode
        // so their own `parent.height` read resolves to something real.
        // Vertical mode is untouched: those widgets size themselves off
        // their own implicitHeight there, not off `parent`.
        if (root.idsNeedingExplicitCrossAxisFill.indexOf(modelData.id) !== -1) {
            loader.Layout.fillHeight = Qt.binding(function () {
                return !root.vertical;
            });
        }
    }

    function resolveEndRadius(modelData) {
        return modelData.last ? root.barRoot.outerRadius : root.barRoot.innerRadius;
    }

    Repeater {
        model: root.layoutConfig.layout.start
        delegate: Loader {
            id: startLoader
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            sourceComponent: BarWidgetMap.componentFor(modelData.id)
            onLoaded: root.wireWidget(startLoader, modelData)
        }
    }

    // Center Group Container
    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true

        GridLayout {
            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rowSpacing: 4
            columnSpacing: 4

            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

            // Calculate target position to be absolutely centered in the
            // bar, on the cross axis.
            property real targetY: {
                if (!parent || !root.barItem)
                    return 0;

                // Force re-evaluation when parent moves
                var _trigger = parent.y;

                var parentPos = parent.mapToItem(root.barItem, 0, 0);
                return (root.barItem.height - height) / 2 - parentPos.y;
            }

            property real targetX: {
                if (!parent || !root.barItem)
                    return 0;

                // Force re-evaluation when parent moves
                var _trigger = parent.x;

                var parentPos = parent.mapToItem(root.barItem, 0, 0);
                return (root.barItem.width - width) / 2 - parentPos.x;
            }

            // Clamp position on the cross axis
            y: root.vertical ? Math.max(0, Math.min(parent.height - height, targetY)) : 0
            x: root.vertical ? 0 : Math.max(0, Math.min(parent.width - width, targetX))

            height: root.vertical ? Math.min(parent.height, implicitHeight) : parent.height
            width: root.vertical ? parent.width : Math.min(parent.width, implicitWidth)

            Repeater {
                model: root.layoutConfig.layout.center
                delegate: Loader {
                    id: centerLoader
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
                    sourceComponent: BarWidgetMap.componentFor(modelData.id)
                    onLoaded: root.wireWidget(centerLoader, modelData)
                }
            }
        }
    }

    Repeater {
        model: root.layoutConfig.layout.end
        delegate: Loader {
            id: endLoader
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            sourceComponent: BarWidgetMap.componentFor(modelData.id)
            onLoaded: root.wireWidget(endLoader, modelData)
        }
    }
}
