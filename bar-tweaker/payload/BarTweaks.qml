pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// BarTweaks: resolves the vertical bar's widget layout from
// ~/.config/ambxst/config/bar-tweaker.json into a flat, render-ready model.
//
// Single responsibility: read + validate + resolve. It does not render
// anything and does not know about BarContent.qml's layout code.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------

    // Widget ids this mod currently knows how to place in the vertical bar.
    // Anything outside this set is dropped (with a warning) on read.
    readonly property var knownWidgetIds: [
        "launcher", "systray", "tools", "presets",
        "layoutSelector", "workspaces", "pin",
        "controls", "battery", "clock", "power"
    ]

    // Reproduces the current hardcoded vanilla vertical layout exactly.
    // Used both as the fallback model and as the file seeded on first run.
    readonly property var defaultConfig: ({
        version: 1,
        vertical: {
            start:  [["launcher", "systray", "tools", "presets"]],
            center: [["layoutSelector", "workspaces", "pin"]],
            end:    [["controls", "battery", "clock", "power"]]
        }
    })

    readonly property string configPath: Config.configDir + "/bar-tweaker.json"

    // ------------------------------------------------------------------
    // File loading
    // ------------------------------------------------------------------

    // Raw file text, re-parsed by the `vertical` binding below whenever it
    // (or Config.bar.showPinButton) changes.
    property string rawText: ""

    FileView {
        id: fileView
        path: root.configPath
        watchChanges: true
        atomicWrites: true
        onLoaded: {
            root.rawText = text();
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
                console.log("BarTweaks: bar-tweaker.json not found, creating default...");
                const defaults = JSON.stringify(root.defaultConfig, null, 2);
                fileView.setText(defaults);
                root.rawText = defaults;
            } else {
                console.warn("BarTweaks: failed to load bar-tweaker.json:", FileViewError.toString(error));
            }
        }
        onFileChanged: reload()
    }

    // ------------------------------------------------------------------
    // Parsing + normalization
    // ------------------------------------------------------------------

    // JSON.parse with fallback to defaults on malformed content. Never throws.
    function parseConfig(text) {
        if (!text || text.trim().length === 0) {
            return root.defaultConfig;
        }
        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || typeof parsed.vertical !== "object") {
                console.warn("BarTweaks: bar-tweaker.json is missing a 'vertical' object, using defaults");
                return root.defaultConfig;
            }
            return parsed;
        } catch (e) {
            console.warn("BarTweaks: malformed bar-tweaker.json, falling back to defaults:", e);
            return root.defaultConfig;
        }
    }

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

    // Whitelists + dedupes ids across the whole vertical layout (start,
    // center, end together - an id may only appear once anywhere). Pill
    // boundaries are preserved; empty pills are dropped.
    function normalizeVertical(configObj) {
        const groupNames = ["start", "center", "end"];
        const seen = {};
        const result = {};

        groupNames.forEach(groupName => {
            const pills = normalizeGroup(configObj.vertical[groupName]);
            const outPills = [];

            pills.forEach(pill => {
                const outPill = [];
                pill.forEach(id => {
                    if (root.knownWidgetIds.indexOf(id) === -1) {
                        console.warn("BarTweaks: unknown widget id '" + id + "' dropped from '" + groupName + "'");
                        return;
                    }
                    if (seen[id]) {
                        console.warn("BarTweaks: duplicate widget id '" + id + "' dropped (keeping first occurrence)");
                        return;
                    }
                    seen[id] = true;
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
    function filterVisibility(normalizedVertical) {
        const showPinButton = (Config.bar && Config.bar.showPinButton !== undefined ? Config.bar.showPinButton : true);
        const result = {};

        ["start", "center", "end"].forEach(groupName => {
            const outPills = [];
            normalizedVertical[groupName].forEach(pill => {
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

    // Recomputes whenever rawText or Config.bar.showPinButton changes.
    readonly property var vertical: {
        const parsed = parseConfig(root.rawText);
        const normalized = normalizeVertical(parsed);
        const filtered = filterVisibility(normalized);
        return {
            start: resolveGroup(filtered.start),
            center: resolveGroup(filtered.center),
            end: resolveGroup(filtered.end)
        };
    }

    // TEMP: remove when Phase 4 wires this into BarContent.qml's layout.
    // Verifies the resolved model in isolation via the Quickshell log.
    onVerticalChanged: {
        console.log("[BarTweaks] TEMP resolved vertical model:", JSON.stringify(root.vertical));
    }
}
