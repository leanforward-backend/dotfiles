import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget: sets how large each app draws its own interface -- the size of
// everything INSIDE the window, not the window itself.
//
// Spotify is Electron, so it takes a fractional Chromium device scale factor
// and is restarted on the spot. Unity reads the GTK scale factor (GDK_SCALE),
// which is integer-only and read at process start, so it offers 1x/2x and
// lands the next time Unity Hub starts.
Panel {
  id: root
  moduleName: "toby.window-scale"
  ipcTarget: "toby.window-scale"

  property real spotifyScale: 0.8
  property int unityScale: 1
  property bool applying: false

  function refresh() {
    if (!readSpotifyProc.running) readSpotifyProc.running = true
    if (!readUnityProc.running) readUnityProc.running = true
  }

  function scriptPath() {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/toby.window-scale/set-scale.sh"
  }

  function applySpotify(v) {
    var scale = Math.round(v * 20) / 20  // snap to 0.05
    root.spotifyScale = scale
    root.applying = true
    applyProc.command = [root.scriptPath(), "spotify", scale.toFixed(2)]
    applyProc.running = true
  }

  function applyUnity(v) {
    var scale = Math.round(v) < 2 ? 1 : 2
    root.unityScale = scale
    applyProc.command = [root.scriptPath(), "unity", String(scale)]
    applyProc.running = true
  }

  Process {
    id: readSpotifyProc
    command: ["bash", "-c",
      "grep -oE '[-]-force-device-scale-factor=[0-9.]+' \"${XDG_CONFIG_HOME:-$HOME/.config}/spotify-flags.conf\" 2>/dev/null | tail -1 | cut -d= -f2"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = parseFloat(String(text).trim())
        if (!isNaN(v) && v > 0) root.spotifyScale = v
      }
    }
  }

  Process {
    id: readUnityProc
    command: ["bash", "-c",
      "cat \"${XDG_CONFIG_HOME:-$HOME/.config}/unity-ui-scale\" 2>/dev/null | tr -dc '0-9' | head -c 2"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = parseInt(String(text).trim(), 10)
        if (v === 1 || v === 2) root.unityScale = v
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.applying = false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⤢"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(12)

        Text {
          text: "UI Scale"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          text: "Size of everything inside the window."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------- Spotify ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(spotifyHdr.implicitHeight, spotifyPct.implicitHeight)

          PanelSectionHeader {
            id: spotifyHdr
            text: "SPOTIFY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: spotifyPct
            text: Math.round((spotifySlider.dragging ? spotifySlider.liveValue : root.spotifyScale) * 100) + "%"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSlider {
          id: spotifySlider
          bar: root.bar
          width: parent.width
          minimum: 0.5
          maximum: 1.25
          step: 0.05
          value: root.spotifyScale
          enabled: !root.applying
          opacity: root.applying ? 0.5 : 1.0
          onReleased: function(v) { root.applySpotify(v) }
        }

        Text {
          width: parent.width
          text: root.applying ? "Restarting Spotify…" : "Restarts Spotify to apply."
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------- Unity ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(unityHdr.implicitHeight, unityPct.implicitHeight)

          PanelSectionHeader {
            id: unityHdr
            text: "UNITY EDITOR"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: unityPct
            text: Math.round((unitySlider.dragging ? unitySlider.liveValue : root.unityScale)) === 2 ? "200%" : "100%"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // GDK_SCALE is an integer, so this is genuinely two stops -- not a
        // continuous range dressed up as one.
        PanelSlider {
          id: unitySlider
          bar: root.bar
          width: parent.width
          minimum: 1
          maximum: 2
          step: 1
          integer: true
          tickCount: 2
          value: root.unityScale
          onReleased: function(v) { root.applyUnity(v) }
        }

        Text {
          width: parent.width
          text: "Applies when Unity Hub next starts. Quit Hub from its tray icon, not just its window."
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Item {
          width: parent.width
          height: Style.space(4)
        }
      }
    }
  }
}
