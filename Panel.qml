import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "awhitaker.mutagen"
  ipcTarget: "awhitaker.mutagen"
  manageIpc: false

  // Items inside the panel's lazily built content, null until first open.
  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null
  readonly property Item searchInput: panel.loadedContent ? panel.loadedContent.searchInput : null

  property string focusSection: "header"
  property int syncIndex: 0
  property int forwardIndex: 0
  property bool cursorActive: false
  property bool searchOpen: false
  property string searchQuery: ""
  property string expandedSessionId: ""
  property string confirmActionKey: ""

  // Row maps populated by rendered SessionRow / ForwardRow delegates for accurate scrollIntoView.
  property var _syncRowMap: ({})
  property var _forwardRowMap: ({})

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color subtleFill: Style.normalFillFor(foreground, accent)
  readonly property color accentFill: Util.alpha(accent, Style.selectedFillAlpha)
  readonly property color urgentFill: Util.alpha(urgent, 0.14)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var summaryObj: mutagen.summary || ({})
  readonly property string summaryState: String(summaryObj.state || (mutagen.installed ? "stopped" : "not-installed"))
  readonly property bool isIssue: summaryState === "issue"
  readonly property bool isSyncing: summaryState === "syncing"
  readonly property bool isPaused: summaryState === "paused"
  readonly property bool isEmpty: summaryState === "empty"
  readonly property bool isCrossed: !mutagen.installed || !mutagen.daemonActive
  readonly property bool dimBarIcon: isCrossed || isPaused || (mutagen.hideWhenEmpty && isEmpty)

  readonly property color barIconColor: isIssue
    ? urgent
    : (isSyncing ? accent : (dimBarIcon ? Qt.darker(barForeground, 1.55) : barForeground))
  readonly property color heroIconColor: isIssue
    ? urgent
    : (isSyncing ? accent : (isCrossed || isPaused ? dim : foreground))
  readonly property string barLabelText: !vertical
    && mutagen.showSessionCount
    && !(mutagen.hideWhenEmpty && isEmpty)
    ? String(summaryObj.barLabel || "")
    : ""
  readonly property string toggleDaemonHint: mutagen.daemonActive ? "Stop Mutagen daemon" : "Start Mutagen daemon"
  readonly property bool actionBusy: mutagen.busy && !mutagen.refreshing
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && mutagen.installed

  readonly property bool hasAnySyncs: (mutagen.syncs || []).length > 0
  readonly property bool hasAnyActiveSync: {
    var list = mutagen.syncs || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && !list[i].paused) return true
    }
    return false
  }

  readonly property var filteredGroups: {
    var groups = mutagen.projectGroups || []
    var q = String(searchQuery || "").trim().toLowerCase()
    if (q === "") return groups
    var result = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (!g) continue
      var groupLabel = String(g.label || "").toLowerCase()
      var groupMatches = groupLabel.indexOf(q) !== -1
      var sessions = g.sessions || []
      var matched = []
      for (var j = 0; j < sessions.length; j++) {
        var s = sessions[j]
        if (!s) continue
        if (groupMatches || sessionMatchesQuery(s, q)) matched.push(s)
      }
      if (matched.length > 0) {
        result.push({
          key: g.key,
          label: g.label,
          isProject: g.isProject,
          projectId: g.projectId,
          sessions: matched
        })
      }
    }
    return result
  }

  readonly property var flatVisibleSyncs: {
    var out = []
    var groups = filteredGroups || []
    for (var i = 0; i < groups.length; i++) {
      var sessions = groups[i] && groups[i].sessions ? groups[i].sessions : []
      for (var j = 0; j < sessions.length; j++) out.push(sessions[j])
    }
    return out
  }

  readonly property var filteredForwards: {
    if (!mutagen.showForwards) return []
    var list = mutagen.forwards || []
    var q = String(searchQuery || "").trim().toLowerCase()
    if (q === "") return list
    var out = []
    for (var i = 0; i < list.length; i++) {
      var f = list[i]
      if (!f) continue
      var hay = (
        String(f.displayName || "") + " " +
        String(f.name || "") + " " +
        String(f.id || "") + " " +
        String(f.sourceLabel || "") + " " +
        String(f.destinationLabel || "") + " " +
        String(f.statusLabel || "")
      ).toLowerCase()
      if (hay.indexOf(q) !== -1) out.push(f)
    }
    return out
  }

  readonly property bool showSyncSection: mutagen.installed && mutagen.daemonActive && flatVisibleSyncs.length > 0
  readonly property bool showForwardSection: mutagen.installed && mutagen.daemonActive && filteredForwards.length > 0

  function sessionMatchesQuery(s, q) {
    var a = s.alpha || {}
    var b = s.beta || {}
    var hay = (
      String(s.displayName || "") + " " +
      String(s.name || "") + " " +
      String(s.id || "") + " " +
      String(s.statusLabel || "") + " " +
      String(s.mode || "") + " " +
      String(s.modeShort || "") + " " +
      String(a.url || "") + " " +
      String(a.shortUrl || "") + " " +
      String(b.url || "") + " " +
      String(b.shortUrl || "")
    ).toLowerCase()
    return hay.indexOf(q) !== -1
  }

  function registerSyncRow(id, item) {
    if (!id) return
    _syncRowMap[id] = item
  }

  function unregisterSyncRow(id, item) {
    if (!id) return
    if (_syncRowMap[id] === item) delete _syncRowMap[id]
  }

  function registerForwardRow(id, item) {
    if (!id) return
    _forwardRowMap[id] = item
  }

  function unregisterForwardRow(id, item) {
    if (!id) return
    if (_forwardRowMap[id] === item) delete _forwardRowMap[id]
  }

  function selectedSync() {
    if (flatVisibleSyncs.length === 0) return null
    return flatVisibleSyncs[Math.max(0, Math.min(syncIndex, flatVisibleSyncs.length - 1))]
  }

  function selectedForward() {
    if (filteredForwards.length === 0) return null
    return filteredForwards[Math.max(0, Math.min(forwardIndex, filteredForwards.length - 1))]
  }

  function syncIndexById(id) {
    for (var i = 0; i < flatVisibleSyncs.length; i++) {
      if (flatVisibleSyncs[i] && flatVisibleSyncs[i].id === id) return i
    }
    return -1
  }

  function toggleExpanded(id) {
    if (!id) return
    expandedSessionId = (expandedSessionId === id) ? "" : id
    confirmActionKey = ""
    confirmTimer.stop()
    Qt.callLater(scrollCursorIntoView)
  }

  function armOrRunDestructive(key, fn) {
    if (confirmActionKey === key) {
      confirmActionKey = ""
      confirmTimer.stop()
      fn()
    } else {
      confirmActionKey = key
      confirmTimer.restart()
    }
  }

  function toggleSearch() {
    if (!mutagen.installed || !mutagen.daemonActive) return
    searchOpen = !searchOpen
    if (searchOpen) {
      Qt.callLater(function() { if (searchInput) searchInput.forceActiveFocus() })
    } else {
      searchQuery = ""
      if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
    }
  }

  function openSearchAndFocus() {
    if (!mutagen.installed || !mutagen.daemonActive) return
    searchOpen = true
    Qt.callLater(function() { if (searchInput) searchInput.forceActiveFocus() })
  }

  function closeSearch() {
    searchQuery = ""
    searchOpen = false
    if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
  }

  function ensureCursor() {
    if (syncIndex >= flatVisibleSyncs.length) syncIndex = Math.max(0, flatVisibleSyncs.length - 1)
    if (syncIndex < 0) syncIndex = 0
    if (forwardIndex >= filteredForwards.length) forwardIndex = Math.max(0, filteredForwards.length - 1)
    if (forwardIndex < 0) forwardIndex = 0

    if (focusSection === "syncs" && !showSyncSection) {
      focusSection = showForwardSection ? "forwards" : "header"
    } else if (focusSection === "forwards" && !showForwardSection) {
      focusSection = showSyncSection ? "syncs" : "header"
    } else if (focusSection !== "header" && focusSection !== "syncs" && focusSection !== "forwards") {
      focusSection = "header"
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setSyncCursorById(id) {
    var idx = syncIndexById(id)
    if (idx < 0) return
    cursorActive = true
    focusSection = "syncs"
    syncIndex = idx
  }

  function setForwardCursor(idx) {
    cursorActive = true
    focusSection = "forwards"
    forwardIndex = Math.max(0, Math.min(filteredForwards.length - 1, idx))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return

    if (focusSection === "header") {
      if (dy > 0) {
        if (showSyncSection) {
          focusSection = "syncs"
          syncIndex = 0
        } else if (showForwardSection) {
          focusSection = "forwards"
          forwardIndex = 0
        }
      }
    } else if (focusSection === "syncs") {
      if (dy < 0) {
        if (syncIndex <= 0) {
          setHeaderCursor()
          return
        }
        syncIndex--
      } else {
        if (syncIndex < flatVisibleSyncs.length - 1) {
          syncIndex++
        } else if (showForwardSection) {
          focusSection = "forwards"
          forwardIndex = 0
        }
      }
    } else if (focusSection === "forwards") {
      if (dy < 0) {
        if (forwardIndex <= 0) {
          if (showSyncSection) {
            focusSection = "syncs"
            syncIndex = flatVisibleSyncs.length - 1
          } else {
            setHeaderCursor()
            return
          }
        } else {
          forwardIndex--
        }
      } else if (forwardIndex < filteredForwards.length - 1) {
        forwardIndex++
      }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      if (mutagen.installed && !root.actionBusy) mutagen.toggleDaemon()
    } else if (focusSection === "syncs") {
      var s = selectedSync()
      if (s) toggleExpanded(s.id)
    } else if (focusSection === "forwards") {
      var f = selectedForward()
      if (f && !root.actionBusy) mutagen.toggleForwardPause(f)
    }
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!panelFlick || !item) return
      var margin = Style.space(8)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) {
        panelFlick.contentY = Math.max(0, top - margin)
      } else if (bottom > viewBottom - margin) {
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
      }
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "header") {
      if (panelFlick) panelFlick.contentY = 0
      return
    }
    if (focusSection === "syncs") {
      var s = selectedSync()
      if (s && _syncRowMap[s.id]) scrollItemIntoView(_syncRowMap[s.id])
    } else if (focusSection === "forwards") {
      var f = selectedForward()
      if (f && _forwardRowMap[f.id]) scrollItemIntoView(_forwardRowMap[f.id])
    }
  }

  function healthColor(health) {
    if (health === "issue") return urgent
    if (health === "syncing") return accent
    if (health === "paused") return dim
    return foreground
  }

  function healthFill(health) {
    if (health === "issue") return urgentFill
    if (health === "syncing") return accentFill
    return subtleFill
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      focusSection = "header"
      syncIndex = 0
      forwardIndex = 0
      confirmActionKey = ""
      confirmTimer.stop()
      if (panelFlick) panelFlick.contentY = 0
      mutagen.refresh()
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    } else {
      searchQuery = ""
      searchOpen = false
      expandedSessionId = ""
      confirmActionKey = ""
      confirmTimer.stop()
    }
  }

  onFlatVisibleSyncsChanged: ensureCursor()
  onFilteredForwardsChanged: ensureCursor()

  Timer {
    id: confirmTimer
    interval: 4000
    repeat: false
    onTriggered: root.confirmActionKey = ""
  }

  TextMetrics {
    id: barLabelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
    text: root.barLabelText
  }

  Service {
    id: mutagen
    settings: root.settings
    panelOpen: root.opened
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { mutagen.refresh(); return "ok" }
    function flushAll(): string { mutagen.flushAll(); return "ok" }
    function pauseAll(): string { mutagen.pauseAll(); return "ok" }
    function resumeAll(): string { mutagen.resumeAll(); return "ok" }
    function startDaemon(): string { mutagen.startDaemon(); return "ok" }
    function stopDaemon(): string { mutagen.stopDaemon(); return "ok" }
    function status(): string { return mutagen.summary ? String(mutagen.summary.statusText || "") : "" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.barIconColor
    labelText: root.barLabelText
    slotSize: root.barLabelText !== "" && !root.vertical
      ? Math.max(Style.bar.iconSlot, Style.bar.iconCanvas + barLabelMetrics.advanceWidth + Style.space(14))
      : Style.bar.iconSlot
    tooltipText: root.summaryObj.tooltipText ? String(root.summaryObj.tooltipText) : "Mutagen"
    pressFeedbackButtons: Qt.LeftButton | Qt.MiddleButton
    iconComponent: Component {
      Item {
        MutagenIcon {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          iconSize: button.iconSize
          color: root.barIconColor
          badgeColor: root.urgent
          syncing: root.isSyncing
          crossed: root.isCrossed
          warning: root.isIssue
          paused: root.isPaused || (mutagen.hideWhenEmpty && root.isEmpty)
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) mutagen.refresh()
      // Right-click intentionally does nothing.
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(410))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(580))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      property alias searchInput: searchInput
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      blocked: searchInput.activeFocus

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          root.ensureCursor()
          if (dy > 0) root.moveCursor(dx, dy)
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (!root.cursorActive) {
          root.cursorActive = true
          root.ensureCursor()
        }
        root.activateCursor()
      }
      onCloseRequested: {
        if (root.searchOpen || root.searchQuery !== "") {
          root.closeSearch()
        } else if (root.confirmActionKey !== "") {
          root.confirmActionKey = ""
          confirmTimer.stop()
        } else if (root.expandedSessionId !== "") {
          root.expandedSessionId = ""
        } else {
          root.close()
        }
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") {
          root.openSearchAndFocus()
          return
        }
        if (t === "r" || t === "R") {
          mutagen.refresh()
          return
        }
        if (t === "F") {
          if (mutagen.daemonActive && root.hasAnySyncs && !root.actionBusy) mutagen.flushAll()
          return
        }
        if (t === "f") {
          var fs = root.focusSection === "syncs" ? root.selectedSync() : null
          if (fs && !fs.paused && !root.actionBusy) mutagen.flushSession(fs.id)
          return
        }
        if (t === "p" || t === "P") {
          if (root.actionBusy) return
          if (root.focusSection === "syncs" && root.selectedSync()) {
            mutagen.toggleSessionPause(root.selectedSync())
          } else if (root.focusSection === "forwards" && root.selectedForward()) {
            mutagen.toggleForwardPause(root.selectedForward())
          } else if (mutagen.daemonActive && root.hasAnySyncs) {
            mutagen.togglePauseAll()
          }
          return
        }
        if (t === "o" || t === "O") {
          var os = root.focusSection === "syncs" ? root.selectedSync() : null
          if (os && os.localPath) mutagen.openLocalPath(os.localPath)
          return
        }
        if (t === "t" || t === "T") {
          var ts = root.focusSection === "syncs" ? root.selectedSync() : null
          if (ts && ts.localPath) mutagen.openLocalTerminal(ts.localPath)
          return
        }
        if (t === "s" || t === "S") {
          var ss = root.focusSection === "syncs" ? root.selectedSync() : null
          if (ss && ss.sshEndpoint) mutagen.openRemoteSsh(ss.sshEndpoint)
        }
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
          spacing: Style.space(10)

          // Hero header
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            // Exposed for hero's trailingControl to avoid PanelHero's `root` id shadowing.
            readonly property bool ringVisible: root.headerHasCursor
            readonly property bool daemonBusy: root.actionBusy
            readonly property string daemonHint: root.toggleDaemonHint
            function focusHero() { root.setHeaderCursor() }
            function toggleDaemon() { if (mutagen.installed && !root.actionBusy) mutagen.toggleDaemon() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Mutagen"
              detail: mutagen.version ? ("v" + mutagen.version) : ""
              meta: String(root.summaryObj.heroMeta || "")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.isCrossed ? 0.55 : 1.0
              iconComponent: Component {
                MutagenIcon {
                  iconSize: Style.font.display
                  color: root.heroIconColor
                  badgeColor: root.urgent
                  syncing: root.isSyncing
                  crossed: root.isCrossed
                  warning: root.isIssue
                  paused: root.isPaused
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: daemonSwitch
                  visible: mutagen.installed
                  checked: mutagen.daemonActive
                  busy: header.daemonBusy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: header.toggleDaemon()

                  PanelToolTip {
                    visible: daemonSwitch.containsMouse
                    text: header.daemonHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          // Global quick-action row
          RowLayout {
            visible: mutagen.installed && mutagen.daemonActive
            width: parent.width
            spacing: Style.space(6)

            Button {
              iconText: "󰑓"
              text: "Flush All"
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              iconSize: Style.font.iconSmall
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              enabled: !root.actionBusy && root.hasAnySyncs
              opacity: enabled ? 1.0 : 0.45
              tooltipText: "Flush all sync sessions (F)"
              onClicked: mutagen.flushAll()
            }

            Button {
              iconText: root.hasAnyActiveSync ? "󰏤" : "󰐊"
              text: root.hasAnyActiveSync ? "Pause All" : "Resume All"
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              iconSize: Style.font.iconSmall
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              enabled: !root.actionBusy && root.hasAnySyncs
              opacity: enabled ? 1.0 : 0.45
              tooltipText: root.hasAnyActiveSync ? "Pause all sync sessions" : "Resume all sync sessions"
              onClicked: mutagen.togglePauseAll()
            }

            Item { Layout.fillWidth: true }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              enabled: !mutagen.refreshing
              onClicked: mutagen.refresh()
            }

            PanelActionButton {
              iconText: "󰍉"
              tooltipText: "Filter sessions (/)"
              foreground: root.searchOpen ? root.accent : root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.toggleSearch()
            }
          }

          // Collapsible search input
          RowLayout {
            visible: root.searchOpen && mutagen.installed && mutagen.daemonActive
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: searchInput
              Layout.fillWidth: true
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              verticalPadding: Style.space(5)
              placeholderText: "Filter sessions & forwards..."
              text: root.searchQuery
              onTextChanged: {
                root.searchQuery = text
                root.syncIndex = 0
                root.forwardIndex = 0
              }
              Keys.onEscapePressed: function(event) {
                root.closeSearch()
                event.accepted = true
              }
              Keys.onDownPressed: function(event) {
                keyCatcher.forceActiveFocus()
                root.cursorActive = true
                if (root.showSyncSection) {
                  root.focusSection = "syncs"
                  root.syncIndex = 0
                } else if (root.showForwardSection) {
                  root.focusSection = "forwards"
                  root.forwardIndex = 0
                }
                root.scrollCursorIntoView()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) {
                keyCatcher.forceActiveFocus()
                if (root.showSyncSection) {
                  root.cursorActive = true
                  root.focusSection = "syncs"
                  root.syncIndex = 0
                  var first = root.selectedSync()
                  if (first) root.toggleExpanded(first.id)
                }
                event.accepted = true
              }
            }

            PanelActionButton {
              visible: root.searchQuery !== ""
              iconText: "󰅖"
              tooltipText: "Clear filter"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.searchQuery = ""
                searchInput.forceActiveFocus()
              }
            }
          }

          // Transient status / error banner
          BorderSurface {
            visible: mutagen.actionStatus !== "" || mutagen.lastError !== ""
            width: parent.width
            implicitHeight: bannerText.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: (mutagen.lastError !== "" && mutagen.actionStatus === "") ? root.urgentFill : root.subtleFill
            borderSpec: (mutagen.lastError !== "" && mutagen.actionStatus === "")
              ? Border.flat(Util.alpha(root.urgent, 0.45), 1)
              : Border.controlSpec("normal", root.foreground, root.accent)

            Text {
              id: bannerText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              textFormat: Text.PlainText
              text: mutagen.actionStatus !== "" ? mutagen.actionStatus : mutagen.lastError
              color: (mutagen.lastError !== "" && mutagen.actionStatus === "") ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          // State card: Mutagen not installed
          CursorSurface {
            visible: !mutagen.installed
            width: parent.width
            implicitHeight: notInstalledCol.implicitHeight + Style.space(20)
            foreground: root.foreground
            bordered: true

            Column {
              id: notInstalledCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              spacing: Style.space(4)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Mutagen CLI not installed"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Install Mutagen and ensure `mutagen` is on your PATH to monitor and control sync sessions."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }

          // State card: Daemon stopped
          CursorSurface {
            visible: mutagen.installed && !mutagen.daemonActive
            width: parent.width
            implicitHeight: stoppedRow.implicitHeight + Style.space(20)
            foreground: root.foreground
            bordered: true

            RowLayout {
              id: stoppedRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: "Mutagen daemon is stopped"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: "Start the daemon to resume file synchronization."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }

              Button {
                iconText: "󰐊"
                text: "Start"
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                iconSize: Style.font.iconSmall
                foreground: root.foreground
                accent: root.accent
                bordered: true
                enabled: !root.actionBusy
                onClicked: mutagen.startDaemon()
              }
            }
          }

          // State card: Empty (daemon running, no sessions or no search matches)
          CursorSurface {
            visible: mutagen.installed && mutagen.daemonActive && !root.showSyncSection && !root.showForwardSection
            width: parent.width
            implicitHeight: emptyText.implicitHeight + Style.space(24)
            foreground: root.foreground
            bordered: true

            Text {
              id: emptyText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              textFormat: Text.PlainText
              text: root.searchQuery.trim() !== ""
                ? ("No sessions match \"" + root.searchQuery.trim() + "\".")
                : "No active Mutagen sessions. Run `mutagen sync create` to start syncing."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          // Sync Sessions section
          PanelSeparator {
            visible: root.showSyncSection
            foreground: root.foreground
          }

          Column {
            visible: root.showSyncSection
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "Sync Sessions (" + root.flatVisibleSyncs.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.filteredGroups
              delegate: Column {
                required property var modelData
                width: parent ? parent.width : 0
                spacing: Style.space(6)

                // Project sub-header with project-level controls
                RowLayout {
                  visible: Boolean(modelData && modelData.isProject)
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: "󰉋"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: modelData ? String(modelData.label || "Project") : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter
                  }

                  PanelActionButton {
                    iconText: "󰑓"
                    tooltipText: "Flush project"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.iconSmall
                    enabled: !root.actionBusy
                    onClicked: mutagen.flushProject(modelData.projectId)
                  }

                  PanelActionButton {
                    iconText: "󰏤"
                    tooltipText: "Pause project"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.iconSmall
                    enabled: !root.actionBusy
                    onClicked: mutagen.pauseProject(modelData.projectId)
                  }

                  PanelActionButton {
                    iconText: "󰐊"
                    tooltipText: "Resume project"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.iconSmall
                    enabled: !root.actionBusy
                    onClicked: mutagen.resumeProject(modelData.projectId)
                  }
                }

                Repeater {
                  model: modelData && modelData.sessions ? modelData.sessions : []
                  delegate: SessionRow {
                    required property var modelData
                    width: parent ? parent.width : 0
                    session: modelData
                  }
                }
              }
            }
          }

          // Network Forwarding section
          PanelSeparator {
            visible: root.showForwardSection
            foreground: root.foreground
          }

          Column {
            visible: root.showForwardSection
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "Forwarding (" + root.filteredForwards.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.filteredForwards
                delegate: ForwardRow {
                  required property var modelData
                  required property int index
                  width: parent ? parent.width : 0
                  forward: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component PillBadge: BorderSurface {
    property string label: ""
    property color textColor: root.dim
    property color fillColor: root.subtleFill
    property color strokeColor: "transparent"

    visible: label !== ""
    implicitWidth: pillText.implicitWidth + Style.space(10)
    implicitHeight: pillText.implicitHeight + Style.space(4)
    radius: Style.cornerRadius
    color: fillColor
    borderSpec: strokeColor !== "transparent" ? Border.flat(strokeColor, 1) : Border.none()

    Text {
      id: pillText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.label
      color: parent.textColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component EndpointDetailRow: CursorSurface {
    id: epRow
    property string sideLabel: ""
    property var endpoint: null

    readonly property string fullUrl: endpoint ? String(endpoint.url || "") : ""
    readonly property bool isConnected: Boolean(endpoint && endpoint.connected)
    readonly property string statsText: {
      if (!endpoint) return ""
      var parts = []
      if (endpoint.files !== undefined && endpoint.files !== null) parts.push(endpoint.files + " files")
      if (endpoint.directories !== undefined && endpoint.directories !== null) parts.push(endpoint.directories + " dirs")
      if (endpoint.sizeText) parts.push(String(endpoint.sizeText))
      return parts.join(" · ")
    }

    foreground: root.foreground
    bordered: false
    implicitHeight: epCol.implicitHeight + Style.space(8)

    MouseArea {
      id: epMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: epRow.fullUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: epRow.fullUrl !== ""
      onClicked: mutagen.copyText(epRow.fullUrl, epRow.sideLabel + " URL")

      PanelToolTip {
        visible: epMouse.containsMouse && epRow.fullUrl !== ""
        text: "Click to copy " + epRow.sideLabel + " URL"
        fontFamily: root.fontFamily
      }
    }

    Column {
      id: epCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: epRow.sideLabel
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Rectangle {
          width: Style.space(6)
          height: width
          radius: width / 2
          color: epRow.isConnected ? root.foreground : root.urgent
          opacity: epRow.isConnected ? 0.85 : 1.0
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          textFormat: Text.PlainText
          text: epRow.isConnected ? "Connected" : "Disconnected"
          color: epRow.isConnected ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item { Layout.fillWidth: true }

        Text {
          visible: epRow.statsText !== ""
          textFormat: Text.PlainText
          text: epRow.statsText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: epRow.fullUrl || "—"
        color: epMouse.containsMouse ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }
  }

  component SessionRow: CursorSurface {
    id: sessionRow
    property var session: null
    property string _registeredId: ""

    readonly property string sessionId: session ? String(session.id || "") : ""
    readonly property string health: session ? String(session.health || "watching") : "watching"
    readonly property bool isExpanded: sessionId !== "" && root.expandedSessionId === sessionId
    readonly property bool isIssueRow: Boolean(session && session.hasIssue)
    readonly property bool isPausedRow: Boolean(session && session.paused)
    readonly property var alphaEp: session && session.alpha ? session.alpha : ({})
    readonly property var betaEp: session && session.beta ? session.beta : ({})
    readonly property string endpointSummary: {
      var a = String(alphaEp.shortUrl || alphaEp.url || "")
      var b = String(betaEp.shortUrl || betaEp.url || "")
      if (a && b) return a + " ↔ " + b
      return a || b
    }
    readonly property string metaSummary: {
      var parts = []
      if (session && session.filesSummary) parts.push(String(session.filesSummary))
      if (session && session.lastSyncedText) parts.push(String(session.lastSyncedText))
      return parts.join(" · ")
    }
    readonly property string resetKey: "reset:" + sessionId
    readonly property string terminateKey: "terminate:" + sessionId
    readonly property bool resetArmed: root.confirmActionKey === resetKey
    readonly property bool terminateArmed: root.confirmActionKey === terminateKey

    function syncRegistration() {
      if (_registeredId !== "" && _registeredId !== sessionId) {
        root.unregisterSyncRow(_registeredId, sessionRow)
      }
      _registeredId = sessionId
      if (sessionId !== "") root.registerSyncRow(sessionId, sessionRow)
    }

    Component.onCompleted: syncRegistration()
    onSessionIdChanged: syncRegistration()
    Component.onDestruction: {
      if (_registeredId !== "") root.unregisterSyncRow(_registeredId, sessionRow)
    }

    hasCursor: root.cursorActive && root.focusSection === "syncs" && root.selectedSync() !== null && root.selectedSync().id === sessionId
    current: isExpanded
    bordered: isIssueRow || isExpanded
    foreground: isIssueRow && !hasCursor ? root.urgent : root.foreground
    accent: root.accent

    implicitHeight: rowCol.implicitHeight + Style.space(16)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setSyncCursorById(sessionRow.sessionId)
      onClicked: root.toggleExpanded(sessionRow.sessionId)
    }

    Column {
      id: rowCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(5)

      // Top line: status dot + name + mode pill + status pill + inline actions
      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(7)
          height: width
          radius: width / 2
          color: root.healthColor(sessionRow.health)
          opacity: sessionRow.isPausedRow ? 0.55 : 1.0
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: session ? String(session.displayName || session.name || session.id) : ""
          color: sessionRow.isPausedRow ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          Layout.alignment: Qt.AlignVCenter
        }

        PillBadge {
          label: session ? String(session.modeShort || "") : ""
          textColor: root.dim
          fillColor: root.subtleFill
          Layout.alignment: Qt.AlignVCenter
        }

        PillBadge {
          label: session ? String(session.statusLabel || "") : ""
          textColor: root.healthColor(sessionRow.health)
          fillColor: root.healthFill(sessionRow.health)
          strokeColor: sessionRow.isIssueRow ? Util.alpha(root.urgent, 0.45) : "transparent"
          Layout.alignment: Qt.AlignVCenter
        }

        PanelActionButton {
          iconText: "󰑓"
          tooltipText: "Flush session (f)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.iconSmall
          enabled: !root.actionBusy && !sessionRow.isPausedRow
          Layout.alignment: Qt.AlignVCenter
          onClicked: mutagen.flushSession(sessionRow.sessionId)
        }

        PanelActionButton {
          iconText: sessionRow.isPausedRow ? "󰐊" : "󰏤"
          tooltipText: sessionRow.isPausedRow ? "Resume session (p)" : "Pause session (p)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.iconSmall
          enabled: !root.actionBusy
          Layout.alignment: Qt.AlignVCenter
          onClicked: mutagen.toggleSessionPause(sessionRow.session)
        }
      }

      // Endpoint line + file/sync metadata
      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: sessionRow.endpointSummary
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        Text {
          visible: sessionRow.metaSummary !== ""
          textFormat: Text.PlainText
          text: sessionRow.metaSummary
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Live staging transfer progress bar
      Column {
        visible: Boolean(session && session.stagingActive)
        width: parent.width
        spacing: Style.space(3)

        Rectangle {
          width: parent.width
          height: Style.space(3)
          radius: height / 2
          color: root.subtleFill
          clip: true

          Rectangle {
            height: parent.height
            radius: parent.radius
            color: root.accent
            width: parent.width * Math.max(0.05, Math.min(1.0, Number(session ? session.stagingProgress : 0) || 0))

            Behavior on width {
              NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
            }
          }
        }

        Text {
          visible: Boolean(session && session.stagingText)
          width: parent.width
          textFormat: Text.PlainText
          text: session ? String(session.stagingText || "") : ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Inline urgent issue callout
      BorderSurface {
        visible: sessionRow.isIssueRow && Boolean(session && session.issueSummary)
        width: parent.width
        implicitHeight: issueRowLayout.implicitHeight + Style.space(8)
        radius: Style.cornerRadius
        color: root.urgentFill
        borderSpec: Border.flat(Util.alpha(root.urgent, 0.45), 1)

        RowLayout {
          id: issueRowLayout
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(6)

          Text {
            text: "!"
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            Layout.alignment: Qt.AlignTop
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: session ? String(session.issueSummary || "") : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      // Expandable Details Drawer
      Column {
        visible: sessionRow.isExpanded
        width: parent.width
        spacing: Style.space(8)

        PanelSeparator {
          foreground: root.foreground
        }

        // Alpha & Beta full URL details (clickable to copy)
        Column {
          width: parent.width
          spacing: Style.space(4)

          EndpointDetailRow {
            width: parent.width
            sideLabel: "Alpha"
            endpoint: sessionRow.alphaEp
          }

          EndpointDetailRow {
            width: parent.width
            sideLabel: "Beta"
            endpoint: sessionRow.betaEp
          }
        }

        // Sync metadata grid
        Flow {
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "Mode: " + String(session && session.mode ? session.mode : "—")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            text: "Cycles: " + String(session && session.successfulCycles !== undefined ? session.successfulCycles : 0)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: Boolean(session && session.lastSyncedText)
            textFormat: Text.PlainText
            text: "Last sync: " + String(session ? session.lastSyncedText : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Conflicts list (click any conflict to copy path)
        Column {
          visible: Boolean(session && session.conflicts && session.conflicts.length > 0)
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Conflicts (" + (session && session.conflicts ? session.conflicts.length : 0) + ")"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Repeater {
            model: session && session.conflicts ? session.conflicts : []
            delegate: BorderSurface {
              id: conflictCard
              required property var modelData
              width: parent ? parent.width : 0
              implicitHeight: conflictCol.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: conflictMouse.containsMouse ? Util.alpha(root.urgent, 0.22) : root.urgentFill
              borderSpec: Border.flat(Util.alpha(root.urgent, 0.4), 1)

              MouseArea {
                id: conflictMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mutagen.copyText(String(modelData.root || ""), "Conflict path")

                PanelToolTip {
                  visible: conflictMouse.containsMouse
                  text: "Click to copy conflict path"
                  fontFamily: root.fontFamily
                }
              }

              Column {
                id: conflictCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(modelData.root || "(root)")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideMiddle
                }

                Text {
                  visible: Boolean(modelData.alphaDesc)
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Alpha: " + String(modelData.alphaDesc || "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: Boolean(modelData.betaDesc)
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Beta: " + String(modelData.betaDesc || "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }

        // Scan problems list
        Column {
          visible: Boolean(session && session.scanProblems && session.scanProblems.length > 0)
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Scan Problems (" + (session && session.scanProblems ? session.scanProblems.length : 0) + ")"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Repeater {
            model: session && session.scanProblems ? session.scanProblems : []
            delegate: Text {
              required property var modelData
              width: parent ? parent.width : 0
              textFormat: Text.PlainText
              text: String(modelData.side || "") + ": " + String(modelData.path || "") + " — " + String(modelData.error || "")
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        // Session lastError detail
        BorderSurface {
          visible: Boolean(session && session.lastError)
          width: parent.width
          implicitHeight: errText.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: root.urgentFill
          borderSpec: Border.flat(Util.alpha(root.urgent, 0.4), 1)

          Text {
            id: errText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            textFormat: Text.PlainText
            text: "Last error: " + String(session ? session.lastError : "")
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // Utility + two-step destructive actions
        Flow {
          width: parent.width
          spacing: Style.space(6)

          Button {
            visible: Boolean(session && session.localPath)
            iconText: "󰉋"
            text: "Open Folder"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.iconSmall
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            tooltipText: "Open local folder (o)"
            onClicked: mutagen.openLocalPath(session.localPath)
          }

          Button {
            visible: Boolean(session && session.localPath)
            iconText: "󰆍"
            text: "Terminal"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.iconSmall
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            tooltipText: "Open terminal in local folder (t)"
            onClicked: mutagen.openLocalTerminal(session.localPath)
          }

          Button {
            visible: Boolean(session && session.sshEndpoint)
            iconText: "󰣀"
            text: "SSH Remote"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.iconSmall
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            tooltipText: "Open SSH session to remote endpoint (s)"
            onClicked: mutagen.openRemoteSsh(session.sshEndpoint)
          }

          Button {
            iconText: "󰆏"
            text: "Copy ID"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.iconSmall
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            tooltipText: "Copy session ID"
            onClicked: mutagen.copyText(sessionRow.sessionId, "Session ID")
          }

          Button {
            iconText: "󰜉"
            text: sessionRow.resetArmed ? "Confirm Reset?" : "Reset"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.iconSmall
            foreground: sessionRow.resetArmed ? root.urgent : root.foreground
            accent: root.urgent
            background: sessionRow.resetArmed ? root.urgentFill : "transparent"
            bordered: true
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            enabled: !root.actionBusy
            tooltipText: sessionRow.resetArmed ? "Click again to reset session history" : "Reset session history (2-step confirm)"
            onClicked: root.armOrRunDestructive(sessionRow.resetKey, function() {
              mutagen.resetSession(sessionRow.sessionId)
            })
          }

          Button {
            iconText: "󰆴"
            text: sessionRow.terminateArmed ? "Confirm Terminate?" : "Terminate"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.iconSmall
            foreground: root.urgent
            accent: root.urgent
            background: sessionRow.terminateArmed ? root.urgentFill : "transparent"
            bordered: true
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            enabled: !root.actionBusy
            tooltipText: sessionRow.terminateArmed ? "Click again to permanently terminate session" : "Terminate sync session (2-step confirm)"
            onClicked: root.armOrRunDestructive(sessionRow.terminateKey, function() {
              mutagen.terminateSession(sessionRow.sessionId)
            })
          }
        }
      }
    }
  }

  component ForwardRow: CursorSurface {
    id: forwardRow
    property var forward: null
    property int rowIndex: 0
    property string _registeredId: ""

    readonly property string fwdId: forward ? String(forward.id || "") : ""
    readonly property string health: forward ? String(forward.health || "active") : "active"
    readonly property bool isPausedRow: Boolean(forward && forward.paused)
    readonly property bool isIssueRow: health === "issue"
    readonly property string terminateKey: "terminate-fwd:" + fwdId
    readonly property bool terminateArmed: root.confirmActionKey === terminateKey

    function syncRegistration() {
      if (_registeredId !== "" && _registeredId !== fwdId) {
        root.unregisterForwardRow(_registeredId, forwardRow)
      }
      _registeredId = fwdId
      if (fwdId !== "") root.registerForwardRow(fwdId, forwardRow)
    }

    Component.onCompleted: syncRegistration()
    onFwdIdChanged: syncRegistration()
    Component.onDestruction: {
      if (_registeredId !== "") root.unregisterForwardRow(_registeredId, forwardRow)
    }

    hasCursor: root.cursorActive && root.focusSection === "forwards" && root.forwardIndex === rowIndex
    bordered: isIssueRow
    foreground: isIssueRow && !hasCursor ? root.urgent : root.foreground
    accent: root.accent

    implicitHeight: fwdCol.implicitHeight + Style.space(14)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setForwardCursor(forwardRow.rowIndex)
      onClicked: if (!root.actionBusy) mutagen.toggleForwardPause(forwardRow.forward)
    }

    Column {
      id: fwdCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(4)

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(7)
          height: width
          radius: width / 2
          color: root.healthColor(forwardRow.health === "active" ? "watching" : forwardRow.health)
          opacity: forwardRow.isPausedRow ? 0.55 : 1.0
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: forward ? String(forward.displayName || forward.name || forward.id) : ""
          color: forwardRow.isPausedRow ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          Layout.alignment: Qt.AlignVCenter
        }

        PillBadge {
          label: forward ? String(forward.statusLabel || "") : ""
          textColor: root.healthColor(forwardRow.health === "active" ? "watching" : forwardRow.health)
          fillColor: root.healthFill(forwardRow.health === "active" ? "watching" : forwardRow.health)
          Layout.alignment: Qt.AlignVCenter
        }

        PanelActionButton {
          iconText: forwardRow.isPausedRow ? "󰐊" : "󰏤"
          tooltipText: forwardRow.isPausedRow ? "Resume forward (p)" : "Pause forward (p)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.iconSmall
          enabled: !root.actionBusy
          Layout.alignment: Qt.AlignVCenter
          onClicked: mutagen.toggleForwardPause(forwardRow.forward)
        }

        Button {
          visible: forwardRow.terminateArmed
          text: "Confirm?"
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          foreground: root.urgent
          accent: root.urgent
          background: root.urgentFill
          bordered: true
          horizontalPadding: Style.space(6)
          verticalPadding: Style.space(2)
          enabled: !root.actionBusy
          Layout.alignment: Qt.AlignVCenter
          onClicked: root.armOrRunDestructive(forwardRow.terminateKey, function() {
            mutagen.terminateForward(forwardRow.fwdId)
          })
        }

        PanelActionButton {
          visible: !forwardRow.terminateArmed
          iconText: "󰅖"
          tooltipText: "Terminate forward (2-step confirm)"
          foreground: root.foreground
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          fontSize: Style.font.iconSmall
          enabled: !root.actionBusy
          Layout.alignment: Qt.AlignVCenter
          onClicked: root.armOrRunDestructive(forwardRow.terminateKey, function() {
            mutagen.terminateForward(forwardRow.fwdId)
          })
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: forward ? (String(forward.sourceLabel || "") + " → " + String(forward.destinationLabel || "")) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        Text {
          textFormat: Text.PlainText
          text: forward ? (String(forward.openConnections || 0) + " open · " + String(forward.totalConnections || 0) + " total") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: Boolean(forward && forward.lastError)
        width: parent.width
        textFormat: Text.PlainText
        text: forward ? String(forward.lastError || "") : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
