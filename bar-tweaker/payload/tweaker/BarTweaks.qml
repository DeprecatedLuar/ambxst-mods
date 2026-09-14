pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// BarTweaks: resolves the bar's widget layout from
// ~/.config/ambxst/config/mods/bar-tweaker/layout.json into a flat,
// render-ready model. One layout section drives the bar in every position.
//
// Single responsibility: read + validate + resolve. It does not render
// anything and does not know about BarContent.qml's layout code.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------

    // Reproduces the current hardcoded vanilla vertical layout exactly.
    // Used both as the fallback model and as the file seeded on first run.
    readonly property var defaultConfig: ({
        version: 1,
        layout: {
            start:  [["launcher", "systray", "tools", "presets"]],
            center: [["layoutSelector", "workspaces", "pin"]],
            end:    [["controls", "battery", "clock", "power"]]
        }
    })

    readonly property string configPath: Config.configDir + "/mods/bar-tweaker/layout.json"
    readonly property string configFolder: Config.configDir + "/mods/bar-tweaker"

    // ------------------------------------------------------------------
    // File loading
    // ------------------------------------------------------------------

    // Raw file text, re-parsed by the `layout` binding below whenever it
    // (or Config.bar.showPinButton) changes.
    property string rawText: ""

    // True once the FileView has settled (loaded or definitively missing).
    // `valid` must not report true off of the FileView's initial empty text.
    property bool fileSettled: false

    // FileView cannot create missing directories, so a FileNotFound is
    // handled by shelling out to `mkdir -p` (as vanilla config/Config.qml
    // does) before writing the seeded defaults.
    Process {
        id: ensureConfigDirProcess
        running: false
        command: ["mkdir", "-p", root.configFolder]
        onExited: {
            const defaults = JSON.stringify(root.defaultConfig, null, 2);
            fileView.setText(defaults);
            root.rawText = defaults;
            root.fileSettled = true;
        }
    }

    FileView {
        id: fileView
        path: root.configPath
        watchChanges: true
        atomicWrites: true
        onLoaded: {
            root.rawText = text();
            root.fileSettled = true;
        }
        onLoadFailed: {
            // NOTE: vanilla config/Config.qml checks
            // `error.toString().includes("FileNotFound")`, but on this
            // Quickshell build FileViewError's default toString() returns
            // the raw enum number (e.g. "2"), not the name - that check
            // never matches, and observably vanilla config files show the
            // same failure-to-regenerate symptom. Compare the enum value
            // directly instead.
            if (error === FileViewError.FileNotFound) {
                console.log("BarTweaks: layout.json not found, creating default...");
                ensureConfigDirProcess.running = true;
            } else {
                console.warn("BarTweaks: failed to load layout.json:", FileViewError.toString(error));
                root.fileSettled = true;
            }
        }
        onFileChanged: reload()
    }

    // ------------------------------------------------------------------
    // Parsing + normalization
    // ------------------------------------------------------------------

    // Parsed config, or null on malformed/empty content. Never throws and
    // never falls back to defaults itself - `valid` reports the outcome so
    // the hook can decide whether to render vanilla instead.
    function parseConfig(text) {
        if (!text || text.trim().length === 0) {
            return null;
        }
        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object") {
                console.warn("BarTweaks: layout.json is not a JSON object");
                return null;
            }
            return parsed;
        } catch (e) {
            console.warn("BarTweaks: malformed layout.json:", e);
            return null;
        }
    }

    readonly property var parsedConfig: parseConfig(root.rawText)

    // False on parse failure, empty text, or no loaded file yet.
    readonly property bool valid: root.fileSettled && root.parsedConfig !== null

    // Whether the mod should render, in every bar position: config valid,
    // the `layout` section exists, and the integrated dock (out of scope)
    // isn't active.
    readonly property bool active: root.valid
        && typeof root.parsedConfig.layout === "object"
        && !(Config.dock && Config.dock.enabled && Config.dock.theme === "integrated")

    // Optional top-level override for the bar's cross-axis size (height when
    // horizontal, width when vertical). Not part of defaultConfig - absent
    // means "use natural content size". Never throws on an invalid value;
    // warns and falls back to natural size instead.
    function isValidBarThickness(value) {
        if (!root.valid || value === undefined) {
            return false;
        }
        if (Number.isInteger(value) && value > 0) {
            return true;
        }
        console.warn("BarTweaks: invalid barThickness '" + value + "', ignored");
        return false;
    }

    readonly property bool barThicknessSet: root.isValidBarThickness(root.valid ? root.parsedConfig.barThickness : undefined)
    readonly property int barThickness: root.barThicknessSet ? root.parsedConfig.barThickness : 0

    // A group's raw value may be a flat id list (shorthand for one pill) or
    // already a list of pills. Normalizes to the latter.
    function normalizeGroup(rawGroup) {
        if (!Array.isArray(rawGroup) || rawGroup.length === 0) {
            return [];
        }
        if (Array.isArray(rawGroup[0])) {
            return rawGroup.map(pill => Array.isArray(pill) ? pill : [pill]);
        }
        return [rawGroup];
    }

    // Whitelists ids across the whole layout. Declarative by design: an id
    // may appear as many times as it's listed, anywhere (same pill,
    // different pill, different group) - the resolved model renders one
    // widget instance per occurrence. Pill boundaries are preserved; empty
    // pills are dropped.
    function normalizeLayout(section) {
        const groupNames = ["start", "center", "end"];
        const knownWidgetIds = Object.keys(BarWidgetMap.registry);
        const result = {};

        groupNames.forEach(groupName => {
            const pills = normalizeGroup(section[groupName]);
            const outPills = [];

            pills.forEach(pill => {
                const outPill = [];
                pill.forEach(id => {
                    if (knownWidgetIds.indexOf(id) === -1) {
                        console.warn("BarTweaks: unknown widget id '" + id + "' dropped from '" + groupName + "'");
                        return;
                    }
                    outPill.push(id);
                });
                if (outPill.length > 0) {
                    outPills.push(outPill);
                }
            });

            result[groupName] = outPills;
        });

        return result;
    }

    // Drops widgets that are conditionally hidden. Must run before first/last
    // is computed, since visibility changes which entry is the pill edge.
    function filterVisibility(normalizedLayout) {
        const showPinButton = (Config.bar && Config.bar.showPinButton !== undefined ? Config.bar.showPinButton : true);
        const result = {};

        ["start", "center", "end"].forEach(groupName => {
            const outPills = [];
            normalizedLayout[groupName].forEach(pill => {
                const outPill = pill.filter(id => id !== "pin" || showPinButton);
                if (outPill.length > 0) {
                    outPills.push(outPill);
                }
            });
            result[groupName] = outPills;
        });

        return result;
    }

    // Flattens a group's pills into { id, first, last } entries. first/last
    // describe position within a pill, not within the whole group.
    function resolveGroup(pills) {
        const out = [];
        pills.forEach(pill => {
            pill.forEach((id, index) => {
                out.push({
                    id: id,
                    first: index === 0,
                    last: index === pill.length - 1
                });
            });
        });
        return out;
    }

    // ------------------------------------------------------------------
    // Resolved model
    // ------------------------------------------------------------------

    // Recomputes whenever the parsed config or Config.bar.showPinButton
    // changes. Only meaningful while `active` is true; the hook never reads
    // it otherwise.
    readonly property var layout: {
        const source = root.valid ? root.parsedConfig.layout : root.defaultConfig.layout;
        const normalized = normalizeLayout(source);
        const filtered = filterVisibility(normalized);
        return {
            start: resolveGroup(filtered.start),
            center: resolveGroup(filtered.center),
            end: resolveGroup(filtered.end)
        };
    }
}
