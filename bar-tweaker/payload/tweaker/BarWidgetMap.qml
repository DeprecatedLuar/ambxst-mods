pragma Singleton
import QtQuick
import Quickshell
import qs.modules.bar
import qs.modules.bar.workspaces
import qs.modules.bar.clock
import qs.modules.bar.systray
import qs.modules.widgets.dashboard
import qs.modules.widgets.powermenu
import qs.modules.widgets.presets

// BarWidgetMap: maps a widget id string (as used in bar-tweaker.json /
// BarTweaks.qml) to the Component that instantiates it.
//
// Single responsibility: id -> Component. It does not know about layout
// order, radii resolution, or BarContent.qml's structure - it only builds
// widgets and wires the fixed properties they always need regardless of
// where they land in the bar.
//
// Consumer contract (for the Loader/createObject call site in BarContent.qml):
// every produced item exposes `startRadius`/`endRadius` (from the existing
// widget contract) plus whatever this map could not supply itself:
//
//   launcher, tools, presets, power   -> nothing extra; set enableShadow,
//                                        startRadius, endRadius.
//   systray, clock, controls,
//   battery, layoutSelector           -> set `barRef` (the BarContent.qml
//                                        `root`), plus enableShadow
//                                        (systray/clock) or layerEnabled
//                                        (controls/battery/layoutSelector),
//                                        startRadius, endRadius.
//   workspaces                        -> set `screen` (root.screen), plus
//                                        startRadius, endRadius. Orientation
//                                        is fixed to "vertical" here since
//                                        this mod is vertical-only.
//   pin                               -> set `toggleHandler` (a function,
//                                        e.g. () => root.pinned = !root.pinned)
//                                        and `pinned` (bool, e.g. bound to
//                                        root.pinned), plus enableShadow,
//                                        startRadius, endRadius.
//
// This map cannot reference a `root` from BarContent.qml (it is a global
// singleton), so any property a widget normally gets from the bar is
// re-exposed as a plain (non-required) property on the wrapped item for the
// consumer to set after instantiation.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // ToggleButton-derived widgets. Each already implements its own
    // `onToggle`, so only the layout-independent-but-fixed-for-this-mod
    // `vertical` needs setting here. `enableShadow`/`startRadius`/
    // `endRadius` are already plain properties the consumer sets directly.
    // ------------------------------------------------------------------

    property Component launcherComponent: Component {
        LauncherButton {
            vertical: true
        }
    }

    property Component toolsComponent: Component {
        ToolsButton {
            vertical: true
        }
    }

    property Component presetsComponent: Component {
        PresetsButton {
            vertical: true
        }
    }

    property Component powerComponent: Component {
        PowerButton {
            vertical: true
        }
    }

    // ------------------------------------------------------------------
    // Bar-aware widgets. Each has a `required property var bar` used only
    // for `bar.orientation` (and, for controls, `bar.screen`). `vertical`
    // derives from `bar.orientation` on these widgets already, so it is
    // left alone rather than hardcoded - it will resolve to true once the
    // consumer wires `barRef` to a vertical-bar root.
    // ------------------------------------------------------------------

    property Component systrayComponent: Component {
        SysTray {
            property var barRef: null
            bar: barRef
        }
    }

    property Component layoutSelectorComponent: Component {
        LayoutSelectorButton {
            property var barRef: null
            bar: barRef
        }
    }

    property Component controlsComponent: Component {
        ControlsButton {
            property var barRef: null
            bar: barRef
        }
    }

    property Component batteryComponent: Component {
        BatteryIndicator {
            property var barRef: null
            bar: barRef
        }
    }

    property Component clockComponent: Component {
        Clock {
            property var barRef: null
            bar: barRef
        }
    }

    // ------------------------------------------------------------------
    // One-offs.
    // ------------------------------------------------------------------

    // Workspaces only ever needs `bar.screen` out of its `bar` property, so
    // the exposed surface is just `screen` - the shim QtObject from vanilla
    // BarContent.qml is reproduced here instead of pushed onto the consumer.
    property Component workspacesComponent: Component {
        Workspaces {
            id: workspacesItem
            property var screen: null
            orientation: "vertical"
            bar: QtObject {
                property var screen: workspacesItem.screen
            }
        }
    }

    // PinButton's `onToggle` is required and application-specific (toggle
    // bar pin state), so it is re-exposed as a plain `toggleHandler`
    // property the consumer binds after instantiation.
    property Component pinComponent: Component {
        PinButton {
            property var toggleHandler: function () {}
            vertical: true
            onToggle: toggleHandler
        }
    }

    // ------------------------------------------------------------------
    // Lookup
    // ------------------------------------------------------------------

    readonly property var registry: ({
            launcher: launcherComponent,
            systray: systrayComponent,
            tools: toolsComponent,
            presets: presetsComponent,
            layoutSelector: layoutSelectorComponent,
            workspaces: workspacesComponent,
            pin: pinComponent,
            controls: controlsComponent,
            battery: batteryComponent,
            clock: clockComponent,
            power: powerComponent
        })

    // Returns the Component for a known widget id, or null for an unknown
    // one. Never throws.
    function componentFor(id) {
        const component = root.registry[id];
        if (!component) {
            console.warn("BarWidgetMap: unknown widget id '" + id + "'");
            return null;
        }
        return component;
    }
}
