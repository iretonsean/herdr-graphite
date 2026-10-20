pragma Singleton
import QtQuick

// Graphite tokens, from docs/design-brief.md and the v2 prototype. No Omarchy component is imported: the
// graphite-ui plugin of the desktop shell needs the shell's own modules (qs.Commons), so the app defines
// the tokens once here.
QtObject {
  readonly property color surface0: "#0e0e10"
  readonly property color surface1: "#18181a"
  readonly property color surface2: "#222224"
  readonly property color surface3: "#2c2c2e"
  readonly property color lift: "#3a3a3c"
  readonly property color text1: "#f5f5f7"
  readonly property color text2: "#e5e5e7"
  readonly property color textSoft: "#c7c7cc"
  readonly property color text3: "#98989d"
  readonly property color text4: "#636366"
  readonly property color accent: "#0a84ff"
  readonly property color labelTint: "#7d8aa3"
  readonly property color ok: "#7fd48f"
  readonly property color warn: "#ffcc66"
  readonly property color error: "#ff8078"
  readonly property color hairline: Qt.rgba(1, 1, 1, 0.05)
  readonly property color highlight: Qt.rgba(1, 1, 1, 0.06)

  readonly property string font: "SF Pro Text, Inter, sans-serif"
  readonly property string mono: "SFMono Nerd Font Mono, SF Mono, monospace"

  // Motion: 120 to 180 ms.
  readonly property int fast: 120
  readonly property int normal: 160
  readonly property int slow: 180

  function stateColor(s) {
    return { needs: warn, working: accent, done: ok, failed: error, ready: text4 }[s] || text4
  }
}
