pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // bin -> { label, flatpak? }
    readonly property var tools: ({
        "ddcutil": { label: "External monitor brightness" },
        "wlsunset": { label: "Night Light" },
        "gpu-screen-recorder": { label: "Screen recording" },
        "tesseract": { label: "OCR" },
        "matugen": { label: "Wallpaper colors" },
        "mpvpaper": { label: "Video wallpapers" },
        "socat": { label: "Video wallpaper tint" },
        "zenity": { label: "File picker" },
        "pavucontrol": { label: "Volume control" },
        "blueman-manager": { label: "Bluetooth manager" },
        "nm-connection-editor": { label: "Network settings" },
        "gradia": { label: "Screenshot editor", flatpak: "be.alexandervanhee.gradia" },
        "tmux": { label: "Tmux sessions" }
    })

    readonly property var flatpakExportDirs: [
        "/var/lib/flatpak/exports/bin",
        Quickshell.env("HOME") + "/.local/share/flatpak/exports/bin"
    ]

    // args: dir1 dir2 entry... ; entry is "bin" or "bin=appid"
    // no tool names are interpolated into the script text itself
    readonly property string probeScript: [
        "d1=\"$1\"; d2=\"$2\"; shift 2",
        "for e in \"$@\"; do",
        "  bin=\"${e%%=*}\"",
        "  appid=\"${e#*=}\"",
        "  if command -v \"$bin\" >/dev/null 2>&1; then",
        "    printf '%s\\n' \"$bin\"",
        "  elif [ \"$appid\" != \"$e\" ] && { [ -x \"$d1/$appid\" ] || [ -x \"$d2/$appid\" ]; }; then",
        "    printf '%s\\n' \"$bin\"",
        "  fi",
        "done"
    ].join("\n")

    property bool ready: false
    property var present: ({})

    function probe() {
        if (probeProcess.running)
            return;

        const entries = Object.keys(tools).map(bin => {
            const flatpak = tools[bin].flatpak;
            return flatpak ? (bin + "=" + flatpak) : bin;
        });

        probeProcess.command = ["sh", "-c", probeScript, "sh", flatpakExportDirs[0], flatpakExportDirs[1]].concat(entries);
        probeProcess.running = true;
    }

    function has(bin) {
        if (!(bin in tools)) {
            console.error("DependencyCheck: unknown tool", bin);
            return true;
        }
        if (!ready)
            return true;
        return present[bin] === true;
    }

    function require(bin) {
        if (has(bin))
            return true;

        Notifications.notifyInternal({
            summary: tools[bin].label + " unavailable",
            body: "Requires `" + bin + "` - not found in PATH.",
            replaceKey: "dep-" + bin,
            appName: "Ambxst"
        });
        probe();
        return false;
    }

    Process {
        id: probeProcess
        running: false
        stdout: StdioCollector {
            id: probeStdout
            onStreamFinished: {
                const found = probeStdout.text.split("\n").map(line => line.trim()).filter(line => line.length > 0);
                const next = {};
                for (const bin of found)
                    next[bin] = true;
                root.present = next;
                root.ready = true;
                console.log("DependencyCheck: present:", found.join(", "));
            }
        }
        onExited: (code) => {
            if (code !== 0)
                console.error("DependencyCheck: probe failed, exit", code);
        }
    }

    Component.onCompleted: probe()
}
