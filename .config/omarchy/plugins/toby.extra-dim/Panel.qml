import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "toby.extra-dim"
  ipcTarget: "toby.extra-dim"

  property int dimPercent: 0
  property int pendingDimPercent: 0
  property int lastDimPercent: 50
  property bool applyQueued: false
  property real wheelAccumulator: 0

  function scriptPath() {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/toby.extra-dim/extra-dim.sh"
  }

  function clampDim(value) {
    return Math.max(0, Math.min(80, Math.round(Number(value))))
  }

  function previewDim(value) {
    root.dimPercent = root.clampDim(value)
    applyDebounce.restart()
  }

  function setDim(value) {
    var dim = root.clampDim(value)
    root.dimPercent = dim
    root.pendingDimPercent = dim
    if (dim > 0) root.lastDimPercent = dim

    if (applyProc.running) {
      root.applyQueued = true
      return
    }

    root.applyQueued = false
    applyProc.command = [root.scriptPath(), "set", String(dim)]
    applyProc.running = true
  }

  function toggleDim() {
    root.setDim(root.dimPercent > 0 ? 0 : root.lastDimPercent)
  }

  function refresh() {
    if (!readProc.running) readProc.running = true
  }

  Component.onCompleted: {
    refresh()
    restoreProc.running = true
  }
  onOpenedChanged: if (opened) refresh()

  Timer {
    id: applyDebounce
    interval: 120
    repeat: false
    onTriggered: root.setDim(root.dimPercent)
  }

  Process {
    id: readProc
    command: [root.scriptPath(), "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text).trim(), 10)
        if (!isNaN(value)) {
          root.dimPercent = root.clampDim(value)
          if (root.dimPercent > 0) root.lastDimPercent = root.dimPercent
        }
      }
    }
  }

  Process {
    id: restoreProc
    command: [root.scriptPath(), "restore"]
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      if (root.applyQueued) root.setDim(root.pendingDimPercent)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dimPercent > 0 ? "󰃞" : "󰃟"
    tooltipText: root.dimPercent > 0 ? "Extra dim: " + root.dimPercent + "%" : "Extra dim: off"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleDim()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      // Match brightness controls: wheel up brightens, wheel down dims.
      root.setDim(root.dimPercent - wheel.steps * 5)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.setDim(root.dimPercent + dx * 5)
        else if (dy !== 0) root.setDim(root.dimPercent + dy * 5)
      }
      onActivateRequested: root.toggleDim()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            text: root.dimPercent > 0 ? "󰃞" : "󰃟"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Extra Dim"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              width: parent.width
            }

            Text {
              text: root.dimPercent > 0 ? "ALL SCREENS" : "OFF"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            text: root.dimPercent + "%"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Item {
          width: parent.width
          implicitHeight: Math.max(dimHeader.implicitHeight, gammaLabel.implicitHeight)

          PanelSectionHeader {
            id: dimHeader
            text: "SOFTWARE DIMMING"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: gammaLabel
            text: "Gamma " + (100 - root.dimPercent) + "%"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSlider {
          id: dimSlider
          bar: root.bar
          width: parent.width
          minimum: 0
          maximum: 80
          step: 1
          integer: true
          value: root.dimPercent
          onMoved: function(value) { root.previewDim(value) }
          onReleased: function(value) {
            applyDebounce.stop()
            root.setDim(value)
          }
        }

        Text {
          width: parent.width
          text: "0% is normal. Higher values darken every display beyond its hardware minimum. Right-click the bar icon to toggle."
          color: Qt.darker(root.bar.foreground, 1.45)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
