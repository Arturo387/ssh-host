import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "arturo.ssh-host"
  ipcTarget: "arturo.ssh-host"

  implicitWidth: 32
  implicitHeight: bar ? bar.barSize : 26

  property var hosts: []
  property var hostState: ({})
  property string selectedHost: ""
  property int actionRefreshes: 0
  property string focusSection: "header"
  property int hostIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool busy: actionRefreshTimer.running

  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("ssh_hosts.py").toString().replace(/^file:\/\//, ""))
  readonly property string displayHost: selectedHost || (hosts.length > 0 ? hosts[0] : "")
  readonly property bool hasControlConnection: !!displayHost && !!hostState[displayHost] && !!hostState[displayHost].connected
  readonly property bool active: {
    for (var host in hostState) {
      if (hostState[host] && hostState[host].connected) return true
    }
    return false
  }

  function stateFor(name) {
    if (!name || !root.hostState[name]) return { connected: false, forwards: [] }
    return root.hostState[name]
  }

  function hostMeta(name) {
    var state = stateFor(name)
    var parts = [state.connected ? "Connected" : "Not connected"]
    var ports = (state.forwards || []).map(function(port) { return ":" + port })
    if (ports.length > 0) parts.push(ports.join(" "))
    return parts.join(" · ")
  }

  function toggleConnection() {
    if (busy || !displayHost) return
    if (hasControlConnection) disconnectHost(displayHost)
    else connectInBackground(displayHost)
  }

  function moveCursor(dx, dy) {
    if (hosts.length === 0) {
      focusSection = "header"
      hostIndex = 0
      cursorActive = true
      return
    }
    cursorActive = true
    if (focusSection === "header") {
      if (dy > 0 && hosts.length > 0) {
        focusSection = "hosts"
        hostIndex = 0
      }
      return
    }
    var next = hostIndex + dy
    if (next < 0) focusSection = "header"
    else hostIndex = Math.max(0, Math.min(next, hosts.length - 1))
  }

  function activateCursor() {
    if (focusSection === "header") toggleConnection()
    else selectHost(hosts[hostIndex])
  }

  function cursorHost() {
    return focusSection === "hosts" && cursorActive && hostIndex < hosts.length
      ? hosts[hostIndex]
      : displayHost
  }

  function syncSelectedHost() {
    var configured = String(settings && settings.host ? settings.host : "").trim()
    hostIndex = root.hosts.length > 0 ? Math.max(0, Math.min(hostIndex, root.hosts.length - 1)) : 0
    if (selectedHost && root.hosts.indexOf(selectedHost) !== -1) return
    selectedHost = configured && root.hosts.indexOf(configured) !== -1
      ? configured
      : (root.hosts.length > 0 ? root.hosts[0] : "")
    if (root.hosts.length === 0) focusSection = "header"
  }

  function refresh() {
    if (!hostProc.running) hostProc.running = true
  }

  Process {
    id: hostProc
    command: ["python3", root.helperPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var payload = JSON.parse(text)
          if (payload && Array.isArray(payload.hosts)) {
            root.hosts = payload.hosts
            root.hostState = payload.state || {}
            root.syncSelectedHost()
          }
        } catch (error) {
          console.warn("SSH host panel state update failed:", error)
        }
      }
    }
  }

  function refreshAfterAction() {
    actionRefreshes = 0
    actionRefreshTimer.restart()
  }

  function connectInBackground(name) {
    var target = name || displayHost
    if (!target) return
    selectedHost = target
    Quickshell.execDetached(["python3", root.helperPath, "connect", target])
    refreshAfterAction()
  }

  function disconnectHost(name) {
    var target = name || displayHost
    if (!target) return
    Quickshell.execDetached(["python3", root.helperPath, "disconnect", target])
    refreshAfterAction()
  }

  function openTerminal(name) {
    var target = name || displayHost
    if (!target) return
    selectedHost = target
    Quickshell.execDetached(["omarchy-launch-terminal", "ssh", target])
    root.close()
  }

  function selectHost(name) {
    if (!name || root.hosts.indexOf(name) === -1) return
    selectedHost = name
    refresh()
  }

  Component.onCompleted: refresh()
  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    focusSection = "header"
    refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.active
    useActiveColor: true
    activeColor: "#7ee787"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  Rectangle {
    id: connectionIndicator
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.topMargin: 4
    width: 8
    height: 8
    radius: 4
    color: root.active ? "#00ff00" : "#555555"
    Behavior on color {
      ColorAnimation { duration: 200 }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "c" || t === "C") root.toggleConnection()
        else if (t === "t" || t === "T") root.openTerminal(root.cursorHost())
        else if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"

            PanelHero {
              id: hero
              width: parent.width
              title: root.displayHost || "SSH"
              meta: !root.displayHost ? "No hosts in ~/.ssh/config"
                : (root.busy ? "Working…" : root.hostMeta(root.displayHost))
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.hasControlConnection ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: connectSwitch
                  visible: !!root.displayHost
                  checked: root.hasControlConnection
                  busy: root.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) {
                    if (on) { root.cursorActive = true; root.focusSection = "header" }
                  }
                  onToggled: root.toggleConnection()

                  PanelToolTip {
                    visible: connectSwitch.containsMouse
                    text: root.hasControlConnection ? "Disconnect background session" : "Connect in background"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: root.hosts.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.hosts.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "HOSTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: hostColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.hosts
                HostRow {
                  required property var modelData
                  required property int index
                  width: hostColumn.width
                  hostName: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component HostRow: CursorSurface {
    id: hostRow
    property string hostName: ""
    property int rowIndex: 0
    readonly property bool connected: root.stateFor(hostName).connected

    hasCursor: root.cursorActive && root.focusSection === "hosts" && root.hostIndex === rowIndex
    current: hostName === root.displayHost
    foreground: root.foreground

    implicitHeight: hostContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "hosts"
        root.hostIndex = hostRow.rowIndex
      }
      onClicked: root.selectHost(hostRow.hostName)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: hostRow.connected ? "" : ""
        color: hostRow.connected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: hostContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: hostRow.hostName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: root.hostMeta(hostRow.hostName)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: ""
        tooltipText: "Open terminal"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openTerminal(hostRow.hostName)
      }
    }
  }

  Timer {
    id: actionRefreshTimer
    interval: 400
    repeat: true
    onTriggered: {
      root.refresh()
      root.actionRefreshes += 1
      if (root.actionRefreshes >= 8) stop()
    }
  }

  Timer {
    interval: Math.min(300, Math.max(5, Number(root.settings && root.settings.refreshIntervalSec) || 30)) * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
}
