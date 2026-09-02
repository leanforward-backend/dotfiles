import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget: sets how large everything drawn INSIDE an app's window is,
// by way of Chromium's device scale factor. Releasing the slider rewrites
// the app's flags file and restarts it, since the scale factor is only read
// at startup.
Panel {
  id: root
  moduleName: "toby.window-scale"
  ipcTarget: "toby.window-scale"

  property real spotifyScale: 0.8
  property bool applying: false

  readonly property real minScale: 0.5
  readonly property real maxScale: 1.25

  function refresh() {
    if (!readProc.running) readProc.running = true
  }

  function applyScale(v) {
    var scale = Math.round(v * 20) / 20  // snap to 0.05
    root.spotifyScale = scale
    root.applying = true
    applyProc.command = [
      Quickshell.env("HOME") + "/.config/omarchy/plugins/toby.window-scale/set-scale.sh",
      "spotify",
      scale.toFixed(2)
    ]
    applyProc.running = true
  }

  // Current value comes from the flags file, so the slider reflects reality
  // even when it was last changed by hand.
  Process {
    id: readProc
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
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

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

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(hdr.implicitHeight, pct.implicitHeight)

          PanelSectionHeader {
            id: hdr
            text: "SPOTIFY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: pct
            text: Math.round((slider.dragging ? slider.liveValue : root.spotifyScale) * 100) + "%"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSlider {
          id: slider
          bar: root.bar
          width: parent.width
          minimum: root.minScale
          maximum: root.maxScale
          step: 0.05
          value: root.spotifyScale
          enabled: !root.applying
          opacity: root.applying ? 0.5 : 1.0
          onReleased: function(v) { root.applyScale(v) }
        }

        Text {
          width: parent.width
          text: root.applying
            ? "Restarting Spotify…"
            : "Releasing the slider restarts Spotify to apply."
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
