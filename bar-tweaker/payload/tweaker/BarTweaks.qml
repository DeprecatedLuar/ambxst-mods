pragma Singleton
import QtQuick
import Quickshell
import qs.config

// BarTweaks: holds one LayoutConfigFile per bar orientation, resolving
// ~/.config/ambxst/config/mods/bar-tweaker/{horizontal,vertical}.json.
//
// Single responsibility: own the two per-orientation config instances and
// expose them keyed by orientation. Parsing/validation/resolution live in
// LayoutConfigFile; this file does not render anything.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------

    readonly property string configFolder: Config.configDir + "/mods/bar-tweaker"
    readonly property string horizontalConfigPath: configFolder + "/horizontal.json"
    readonly property string verticalConfigPath: configFolder + "/vertical.json"

    // ------------------------------------------------------------------
    // Per-orientation config instances
    // ------------------------------------------------------------------

    LayoutConfigFile {
        id: horizontalConfig
        configPath: root.horizontalConfigPath
        configFolder: root.configFolder
    }

    LayoutConfigFile {
        id: verticalConfig
        configPath: root.verticalConfigPath
        configFolder: root.configFolder
    }

    // Keys match vanilla BarContent.qml's `orientation` values exactly.
    readonly property var byOrientation: ({
        horizontal: horizontalConfig,
        vertical: verticalConfig
    })
}
