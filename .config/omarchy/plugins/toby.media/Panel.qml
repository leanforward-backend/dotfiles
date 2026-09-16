import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

// Bar widget: one row per MPRIS source, click to play/pause that source, and a
// pin that decides which source the hardware media keys drive.
//
// Playback control talks to MPRIS directly rather than through omarchy.media:
// a third-party bar-widget plugin is not granted firstPartyServiceFor(), so
// that service is out of reach from here (see shell.qml pluginShellFor).
//
// The pin is a file, not shell state. bindings.lua routes the media keys
// through media-keys.sh, which reads it and falls back to omarchy's own media
// service -- "whatever is playing" -- whenever nothing is pinned.
Panel {
  id: root
  moduleName: "toby.media"
  ipcTarget: "toby.media"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: root.pickActive()
  readonly property bool anyPlaying: root.activePlayer !== null && root.activePlayer.isPlaying

  // Tail of the MPRIS bus name of the pinned player ("spotify", "chromium"),
  // or "" for omarchy's default "whatever is playing" behaviour.
  property string pinned: ""

  readonly property int seekSeconds: 15

  function scriptPath() {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/toby.media/media-keys.sh"
  }

  // org.mpris.MediaPlayer2.chromium.instance81932 -> "chromium". The instance
  // suffix is per-process, so only the stem is stable enough to pin.
  function playerName(player) {
    var bus = String(player && player.dbusName || "")
    var name = bus.replace(/^org\.mpris\.MediaPlayer2\./, "")
    return name.replace(/\.instance\d+$/, "")
  }

  function labelFor(player) {
    if (!player) return "Media source"
    return player.identity || root.playerName(player) || "Media source"
  }

  function detailFor(player) {
    if (!player) return ""
    var title = player.trackTitle || ""
    var artist = player.trackArtist || ""
    if (title && artist) return title + "  ·  " + artist
    return title || artist
  }

  function isPinned(player) {
    return root.pinned !== "" && root.playerName(player) === root.pinned
  }

  // What the bar glyph and its tooltip describe: the pinned source if it is
  // still around, otherwise the first playing one, otherwise the first source.
  function pickActive() {
    var list = root.players
    var playing = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      if (root.pinned !== "" && root.playerName(p) === root.pinned) return p
      if (!playing && p.isPlaying) playing = p
    }
    return playing || (list.length > 0 ? list[0] : null)
  }

  // Seeking goes through the same script the media keys use: Chrome advertises
  // MPRIS CanSeek and then ignores relative Seek, so the jump has to be an
  // absolute SetPosition, and there is no reason to have two versions of that.
  function seek(player, direction) {
    if (!player || !player.canSeek) return
    Util.execArgv([root.scriptPath(), direction === 1 ? "forward" : "back",
      String(root.seekSeconds), root.playerName(player)])
  }

  function skip(player, direction) {
    if (!player) return
    if (direction === 1 && player.canGoNext) player.next()
    else if (direction === -1 && player.canGoPrevious) player.previous()
  }

  function togglePlayback(player) {
    if (!player) return
    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
  }

  function setPinned(name) {
    root.pinned = name
    pinProc.command = name === ""
      ? [root.scriptPath(), "unpin"]
      : [root.scriptPath(), "pin", name]
    pinProc.running = true
  }

  function togglePin(player) {
    root.setPinned(root.isPinned(player) ? "" : root.playerName(player))
  }

  function refresh() {
    if (!readPinProc.running) readPinProc.running = true
  }

  Process {
    id: readPinProc
    command: [root.scriptPath(), "target"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pinned = String(text).trim()
    }
  }

  Process {
    id: pinProc
    stdout: StdioCollector { waitForEnd: true }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰝚"
    dimmed: !root.anyPlaying
    tooltipText: root.activePlayer
      ? (root.labelFor(root.activePlayer)
        + (root.detailFor(root.activePlayer) ? " — " + root.detailFor(root.activePlayer) : ""))
      : "No media sources"
    onPressed: function(b) {
      // Middle click is the shortcut for the common case; everything else
      // opens the panel.
      if (b === Qt.MiddleButton) root.togglePlayback(root.activePlayer)
      else root.toggle()
    }
    // Scrubbing without opening anything: omarchy's own media widget spends
    // the wheel on track skips, but tracks are one key away and a 15s jump
    // isn't.
    onWheelMoved: function(delta) {
      root.seek(root.activePlayer, delta > 0 ? 1 : -1)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
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
          textFormat: Text.PlainText
          text: "Media Sources"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Play/pause, skip tracks, or jump " + root.seekSeconds
            + "s. Pin a source to send the media keys there."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          text: "SOURCES"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          width: parent.width
          visible: root.players.length === 0
          textFormat: Text.PlainText
          text: "Nothing is registered on MPRIS right now."
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          id: sourceList
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.players

            BorderSurface {
              id: sourceRow
              required property var modelData

              readonly property var player: modelData
              readonly property bool pinnedHere: root.isPinned(player)
              readonly property bool seekable: !!player && player.canSeek
              readonly property bool hasNext: !!player && player.canGoNext
              readonly property bool hasPrevious: !!player && player.canGoPrevious

              width: sourceList.width
              height: sourceInner.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              color: pinnedHere
                ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                : (rowHover.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
              borderSpec: pinnedHere
                ? Border.controlSpec("normal", root.bar.foreground, Color.accent)
                : Border.none()

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePlayback(sourceRow.player)
              }

              // Declared after rowHover so the content -- and the pin hit area
              // inside it -- stacks above the row-wide handler. The labels
              // ignore mouse events, so a click anywhere else still falls
              // through to rowHover.
              Row {
                id: sourceInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
                anchors.rightMargin: sourceRow.borderRight + Style.space(8)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  // The six icon slots (18 + 18 + 20 + 20 + 18 + 18) and the
                  // six gaps between the row's seven children.
                  width: parent.width - Style.space(160)
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: root.labelFor(sourceRow.player)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: sourceRow.pinnedHere
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.detailFor(sourceRow.player)
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }

                Item {
                  id: prevSlot
                  width: Style.space(18)
                  height: prevGlyph.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: prevGlyph
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󰑟"
                    color: sourceRow.hasPrevious
                      ? Qt.darker(root.bar.foreground, prevHover.containsMouse ? 1.0 : 1.5)
                      : Qt.darker(root.bar.foreground, 2.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: prevHover
                    anchors.fill: parent
                    anchors.margins: -Style.space(2)
                    hoverEnabled: true
                    enabled: sourceRow.hasPrevious
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.skip(sourceRow.player, -1)
                  }
                }

                Item {
                  id: backSlot
                  width: Style.space(20)
                  height: backGlyph.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: backGlyph
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󱥆"
                    color: sourceRow.seekable
                      ? Qt.darker(root.bar.foreground, backHover.containsMouse ? 1.0 : 1.5)
                      : Qt.darker(root.bar.foreground, 2.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.icon
                  }

                  MouseArea {
                    id: backHover
                    anchors.fill: parent
                    anchors.margins: -Style.space(2)
                    hoverEnabled: true
                    enabled: sourceRow.seekable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.seek(sourceRow.player, -1)
                  }
                }

                Item {
                  id: forwardSlot
                  width: Style.space(20)
                  height: forwardGlyph.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: forwardGlyph
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󱤺"
                    color: sourceRow.seekable
                      ? Qt.darker(root.bar.foreground, forwardHover.containsMouse ? 1.0 : 1.5)
                      : Qt.darker(root.bar.foreground, 2.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.icon
                  }

                  MouseArea {
                    id: forwardHover
                    anchors.fill: parent
                    anchors.margins: -Style.space(2)
                    hoverEnabled: true
                    enabled: sourceRow.seekable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.seek(sourceRow.player, 1)
                  }
                }

                Item {
                  id: nextSlot
                  width: Style.space(18)
                  height: nextGlyph.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: nextGlyph
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󰈑"
                    color: sourceRow.hasNext
                      ? Qt.darker(root.bar.foreground, nextHover.containsMouse ? 1.0 : 1.5)
                      : Qt.darker(root.bar.foreground, 2.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: nextHover
                    anchors.fill: parent
                    anchors.margins: -Style.space(2)
                    hoverEnabled: true
                    enabled: sourceRow.hasNext
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.skip(sourceRow.player, 1)
                  }
                }

                Item {
                  id: pinSlot
                  width: Style.space(18)
                  height: pinGlyph.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: pinGlyph
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: sourceRow.pinnedHere ? "󰐃" : "󰐄"
                    color: sourceRow.pinnedHere
                      ? root.bar.foreground
                      : Qt.darker(root.bar.foreground, pinHover.containsMouse ? 1.2 : 2.2)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: pinHover
                    anchors.fill: parent
                    anchors.margins: -Style.space(2)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePin(sourceRow.player)
                  }
                }
              }

            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.pinned === ""
            ? "Media keys: whatever is playing (omarchy default). SHIFT + next/prev jumps "
              + root.seekSeconds + "s."
            : "Media keys: " + root.pinned + ". SHIFT + next/prev jumps "
              + root.seekSeconds + "s. Click the pin again for automatic."
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
