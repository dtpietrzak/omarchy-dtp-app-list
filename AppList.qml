import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "AppList.js" as AppList

// Menu kind: the shell only injects appLibrary into menu plugins.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  property bool opened: false
  property bool viewReady: false
  property string filterText: ""
  property int selectedIndex: -1
  // With the bar at the bottom the card is turned over: the search field sits
  // at the bottom and the list grows up from it, first row nearest the field.
  readonly property bool flipped: corner.position === "bottom"
  property var apps: []
  property var pinnedIds: ({})
  property var menuEntry: null
  property int menuIndex: 0
  property point menuPoint
  property var uninstallEntry: null
  // iconSource() reads the shell icon index through a callback a binding
  // cannot track, so this forces icons to resolve again after a refresh.
  property int iconRevision: 0

  // Sized like the app list in workspace control: an icon a half larger than
  // the text, rows one padding taller, and a search line with room around it.
  readonly property int edge: Style.spacing.md
  readonly property int iconSize: Math.round(Style.font.body * 1.5)
  readonly property int rowHeight: iconSize + edge
  readonly property int visibleRows: 12
  readonly property int fieldHeight: iconSize + Math.round(edge * 2.5)
  readonly property int gutter: Style.space(10)
  readonly property int cardWidth: Math.min(Style.space(300), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(fieldHeight + rowHeight * visibleRows + Math.round(edge / 2), panel.height - corner.barThickness - Style.gapsOut)

  // The card background follows the bar (opaque, glassy or clear), as workspace
  // control's cards do. A clear bar still gets a backing so text reads.
  readonly property var barConfig: root.shell ? root.shell.barConfig : null
  readonly property color cardColor: {
    var bar = root.barConfig || {}
    var look = bar.background || (bar.transparent === true ? "none" : "opaque")
    var base = Commons.Color.bar.background
    if (look === "glassy") return Qt.rgba(base.r, base.g, base.b, Math.min(base.a, 0.35))
    return base
  }

  readonly property bool menuPinned: {
    var id = AppList.normalizeDesktopId(root.menuEntry && root.menuEntry.id)
    return !!id && root.pinnedIds[id] === true
  }
  readonly property var menuItems: [
    { id: "open", label: strings.t("menu.open") },
    { id: "pin", label: root.menuPinned ? strings.t("menu.removeFromDock") : strings.t("menu.keepInDock") },
    { id: "uninstall", label: strings.t("menu.uninstall") }
  ]
  readonly property string uninstallLabel: AppList.plainLabel(
    root.appLibrary && root.uninstallEntry ? root.appLibrary.entryName(root.uninstallEntry) : "",
    120)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open(payloadJson) {
    root.menuEntry = null
    root.uninstallEntry = null
    root.menuIndex = 0
    root.filterText = ""
    if (searchField.text !== "") searchField.text = ""
    root.opened = true
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.iconRevision++
    root.rebuild(true)
    iconRefresh.restart()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.menuEntry = null
    root.uninstallEntry = null
  }

  function dismiss() {
    root.close()
    var id = (root.manifest && root.manifest.id) || "dtpietrzak.applist"
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(id)
  }

  function loadPins(raw) {
    var config = null
    try { config = JSON.parse(String(raw || "")) } catch (e) { config = null }
    if (!config) return
    root.pinnedIds = AppList.pinnedMap(config)
  }

  function rebuild(resetSelection) {
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    if (!Array.isArray(rows)) rows = []
    var next = []
    var limit = Math.min(rows.length, 400)
    for (var i = 0; i < limit; i++) {
      if (rows[i] && rows[i].entry) next.push(rows[i].entry)
    }
    root.apps = next
    root.selectedIndex = resetSelection
      ? AppList.closestIndex(next.length)
      : AppList.moveIndex(root.selectedIndex, 0, next.length)
    if (!root.viewReady) return
    if (resetSelection) list.positionViewAtBeginning()
    else if (root.selectedIndex >= 0) list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(text) {
    var value = String(text || "")
    if (value.length > 200) value = value.slice(0, 200)
    if (value === root.filterText) return
    root.filterText = value
    if (searchField.text !== value) searchField.text = value
    root.rebuild(true)
  }

  function select(delta) {
    if (root.apps.length === 0) return
    // Up is toward the top of the card, which is higher in a flipped list.
    root.selectedIndex = AppList.moveIndex(root.selectedIndex, root.flipped ? -delta : delta, root.apps.length)
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function launchEntry(entry) {
    if (!entry || !root.appLibrary) return
    var id = AppList.desktopId(entry.id)
    if (!id) return
    var name = AppList.plainLabel(root.appLibrary.entryName(entry), 120)
    root.dismiss()
    root.appLibrary.launch(id, name)
  }

  function launch(index) {
    if (index < 0 || index >= root.apps.length) return
    root.launchEntry(root.apps[index])
  }

  function openMenu(entry, index, point) {
    root.selectedIndex = index
    root.menuIndex = 0
    root.menuEntry = entry
    root.menuPoint = point
  }

  function togglePin(entry) {
    var saved = AppList.desktopId(entry && entry.id)
    var id = AppList.normalizeDesktopId(saved)
    if (!saved || !id) return
    var pinned = root.pinnedIds[id] === true
    var next = ({})
    for (var key in root.pinnedIds) next[key] = true
    if (pinned) delete next[id]
    else next[id] = true
    root.pinnedIds = next
    Util.execArgv(["omarchy", "dock", pinned ? "unpin" : "pin", saved])
  }

  function requestUninstall(entry) {
    if (!entry) return
    root.menuEntry = null
    uninstallConfirm.selectedIndex = 1
    root.uninstallEntry = entry
  }

  function triggerMenu() {
    var item = root.menuItems[root.menuIndex]
    var entry = root.menuEntry
    if (!item || !entry) return
    if (item.id === "open") root.launchEntry(entry)
    else if (item.id === "pin") {
      root.togglePin(entry)
      root.menuEntry = null
    } else if (item.id === "uninstall") root.requestUninstall(entry)
  }

  function handleMenuKey(event) {
    if (event.key === Qt.Key_Escape) root.menuEntry = null
    else if (event.key === Qt.Key_Up) root.menuIndex = AppList.moveIndex(root.menuIndex, -1, root.menuItems.length)
    else if (event.key === Qt.Key_Down) root.menuIndex = AppList.moveIndex(root.menuIndex, 1, root.menuItems.length)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.triggerMenu()
  }

  function handleSearchKey(event) {
    if (root.uninstallEntry) {
      uninstallConfirm.handleKey(event)
      event.accepted = true
      return
    }
    if (root.menuEntry) {
      root.handleMenuKey(event)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up) root.select(-1)
    else if (event.key === Qt.Key_Down) root.select(1)
    else if (event.key === Qt.Key_PageUp) root.select(-root.visibleRows)
    else if (event.key === Qt.Key_PageDown) root.select(root.visibleRows)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.launch(root.selectedIndex)
    else if (event.key === Qt.Key_Escape) {
      if (root.filterText) root.setFilter("")
      else root.dismiss()
    } else return
    event.accepted = true
  }

  // The blur rule for a glassy bar, which Hyprland forgets on every reload.
  function setUpHyprland() {
    var path = decodeURIComponent(String(Qt.resolvedUrl("hypr/applist.lua")).replace(/^file:\/\//, ""))
    Hyprland.dispatch('(function() dofile(' + JSON.stringify(path) + ') end)')
  }

  Component.onCompleted: { root.viewReady = true; root.setUpHyprland() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") root.setUpHyprland()
    }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened) root.rebuild(root.filterText.length > 0) }
  }

  Timer {
    id: iconRefresh
    interval: 800
    onTriggered: if (root.opened) root.iconRevision++
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPins(text())
    onFileChanged: reload()
  }

  StartCorner { id: corner }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "dtpietrzak-applist"

    // No dim behind the card. A click outside it still closes the list.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: {
        if (root.menuEntry) root.menuEntry = null
        else if (!root.uninstallEntry) root.dismiss()
      }
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      // Against the bar with no gap: square on that side, rounded on the others.
      x: corner.position === "left" ? corner.barThickness
        : corner.position === "right" ? panel.width - width - corner.barThickness
        // Under the line between the menu button and the app list button: one
        // bar slot past the menu button, and a little more.
        : corner.cardX(panel.width, width) + (corner.vertical ? 0 : (corner.atRight ? -1 : 1) * (corner.barThickness + 3))
      y: corner.position === "top" ? corner.barThickness
        : corner.position === "bottom" ? Math.max(0, panel.height - height - corner.barThickness)
        : corner.cardY(panel.height, height)
      radius: Style.cornerRadius
      topLeftRadius: corner.position === "top" || corner.position === "left" ? 0 : Style.cornerRadius
      topRightRadius: corner.position === "top" || corner.position === "right" ? 0 : Style.cornerRadius
      bottomLeftRadius: corner.position === "bottom" || corner.position === "left" ? 0 : Style.cornerRadius
      bottomRightRadius: corner.position === "bottom" || corner.position === "right" ? 0 : Style.cornerRadius
      color: root.cardColor

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
          if (!root.uninstallEntry) root.menuEntry = null
        }
      }

      ConfirmDialog {
        id: uninstallConfirm
        anchors.fill: parent
        opened: !!root.uninstallEntry
        z: 10
        message: AppList.format(strings.t("uninstall.confirm"), root.uninstallLabel)
        confirmText: strings.t("uninstall.action")
        background: Commons.Color.bar.background
        foreground: Commons.Color.foreground
        scrim: "transparent"
        selectedBackground: Style.hoverFill
        selectedText: Commons.Color.foreground
        fontFamily: Style.font.family
        cornerRadius: Style.cornerRadius
        onCanceled: {
          root.uninstallEntry = null
          Qt.callLater(function() { searchField.forceActiveFocus() })
        }
        onConfirmed: {
          var entry = root.uninstallEntry
          var id = AppList.desktopId(entry && entry.id)
          var name = root.uninstallLabel
          root.uninstallEntry = null
          root.dismiss()
          if (id && root.appLibrary) root.appLibrary.remove(id, name)
        }
      }

      Item {
        id: fieldBox
        y: root.flipped ? parent.height - height : 0
        width: parent.width
        height: root.fieldHeight

        TextInput {
          id: searchField
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.edge + root.edge / 2
          anchors.rightMargin: root.edge + root.edge / 2
          // Half an edge of card padding above, a full edge below.
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: root.flipped ? root.edge / 4 : -root.edge / 4
          focus: true
          clip: true
          selectByMouse: true
          readOnly: !!root.menuEntry || !!root.uninstallEntry
          color: Commons.Color.foreground
          selectionColor: Style.selectionFillFor(Commons.Color.foreground, Commons.Color.accent)
          selectedTextColor: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          onTextChanged: if (text !== root.filterText) root.setFilter(text)
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleSearchKey(event) }
        }

        Text {
          anchors.left: searchField.left
          anchors.right: searchField.right
          anchors.verticalCenter: searchField.verticalCenter
          visible: searchField.text.length === 0 && searchField.preeditText.length === 0
          textFormat: Text.PlainText
          text: strings.t("search.placeholder")
          color: Commons.Color.foreground
          opacity: 0.45
          font.family: searchField.font.family
          font.pixelSize: searchField.font.pixelSize
          elide: Text.ElideRight
        }

        // The shortcut that opens this list, while the field is empty.
        Text {
          anchors.right: parent.right
          anchors.rightMargin: root.edge + root.edge / 2
          anchors.verticalCenter: searchField.verticalCenter
          visible: searchField.text.length === 0 && searchField.preeditText.length === 0
          textFormat: Text.PlainText
          text: strings.t("search.shortcut")
          color: Commons.Color.foreground
          opacity: 0.3
          font.family: searchField.font.family
          font.pixelSize: searchField.font.pixelSize
        }
      }

      ListView {
        id: list
        y: root.flipped ? Math.round(root.edge / 2) : fieldBox.height
        x: Math.round(root.edge / 2)
        width: parent.width - root.edge - root.gutter
        height: parent.height - fieldBox.height - Math.round(root.edge / 2)
        model: root.apps
        clip: true
        verticalLayoutDirection: root.flipped ? ListView.BottomToTop : ListView.TopToBottom
        spacing: 0
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: root.rowHeight * 8
        // The flickable's own wheel step is a few pixels, under one row.
        maximumFlickVelocity: 8000
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var pixels = event.pixelDelta.y
            var angle = event.angleDelta.y
            // A mouse notch is 120 angle units. Trackpads send pixel movement
            // with a smaller angle, so those keep a scaled pixel step.
            var delta = Math.abs(angle) >= 120
              ? angle / 120 * root.rowHeight * 3
              : (pixels !== 0 ? pixels * 2 : angle / 120 * root.rowHeight * 3)
            if (delta === 0) return
            var bottom = list.originY + Math.max(0, list.contentHeight - list.height)
            list.contentY = Math.max(list.originY, Math.min(bottom, list.contentY - delta))
            event.accepted = true
          }
        }

        delegate: Item {
          id: row
          required property int index
          required property var modelData
          readonly property bool selected: index === root.selectedIndex

          width: list.width
          height: root.rowHeight

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: row.selected ? Style.hoverFill : "transparent"
            border.width: row.selected ? 1 : 0
            border.color: Commons.Color.accent
          }

          // A thin line between this row and the next.
          Rectangle {
            y: Math.round(parent.height - height / 2)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.edge
            anchors.rightMargin: root.edge
            height: 1 / Math.max(1, Screen.devicePixelRatio)
            visible: row.index < root.apps.length - 1 && !row.selected && row.index + 1 !== root.selectedIndex
            color: Qt.alpha(Commons.Color.foreground, 0.15)
          }

          Image {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.edge
            width: root.iconSize
            height: root.iconSize
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            source: (root.iconRevision >= 0 && root.appLibrary) ? root.appLibrary.iconSource(row.modelData.icon) : ""
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: icon.right
            anchors.leftMargin: root.edge
            anchors.right: parent.right
            anchors.rightMargin: root.edge
            text: root.appLibrary ? root.appLibrary.entryName(row.modelData) : ""
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onContainsMouseChanged: if (containsMouse && !root.menuEntry && !root.uninstallEntry) root.selectedIndex = row.index
            onClicked: function(event) {
              if (event.button === Qt.RightButton) {
                root.openMenu(row.modelData, row.index, row.mapToItem(panel.contentItem, event.x, event.y))
                return
              }
              root.menuEntry = null
              root.launch(row.index)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.flipped ? parent.height - fieldBox.height - height - Style.space(24) : fieldBox.height + Style.space(24)
        width: parent.width - Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        visible: root.apps.length === 0
        text: root.filterText
          ? AppList.format(strings.t("list.empty"), AppList.plainLabel(root.filterText, 80))
          : strings.t("list.emptyAll")
        color: Commons.Color.foreground
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    BorderSurface {
      id: menu
      visible: !!root.menuEntry && !root.uninstallEntry
      z: 2
      width: Math.max(Style.space(180), menuColumn.implicitWidth) + padding * 2
      height: menuColumn.implicitHeight + padding * 2
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(Math.max(Style.gapsOut, root.menuPoint.x), panel.width - width - Style.gapsOut)
      y: Math.min(Math.max(Style.gapsOut, root.menuPoint.y), panel.height - height - Style.gapsOut)
      radius: Style.cornerRadius
      color: Commons.Color.bar.background
      borderSpec: Border.none()
      padding: Style.spacing.sm

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: menuColumn
        x: menu.contentLeftInset
        y: menu.contentTopInset
        width: menu.width - menu.contentLeftInset - menu.contentRightInset

        Repeater {
          model: root.menuItems

          delegate: Rectangle {
            id: menuRow
            required property int index
            required property var modelData

            implicitWidth: menuLabel.implicitWidth + Style.spacing.controlPaddingX * 2
            width: menuColumn.width
            height: Style.spacing.popupRowHeight
            radius: Style.cornerRadius
            color: menuRow.index === root.menuIndex ? Style.hoverFill : "transparent"
            border.width: menuRow.index === root.menuIndex ? 1 : 0
            border.color: Commons.Color.accent

            Text {
              id: menuLabel
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.controlPaddingX
              text: menuRow.modelData.label
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.menuIndex = menuRow.index
              onClicked: {
                root.menuIndex = menuRow.index
                root.triggerMenu()
              }
            }
          }
        }
      }
    }
  }
}
