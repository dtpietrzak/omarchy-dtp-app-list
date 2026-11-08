import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import Quickshell
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
  property var apps: []
  property var pinnedIds: ({})
  property var menuEntry: null
  property int menuIndex: 0
  property point menuPoint
  property var uninstallEntry: null
  // iconSource() reads the shell icon index through a callback a binding
  // cannot track, so this forces icons to resolve again after a refresh.
  property int iconRevision: 0

  readonly property int iconSize: Style.space(16)
  readonly property int rowHeight: Math.max(Style.spacing.popupRowHeight, Style.font.body + Style.space(8))
  readonly property int visibleRows: 12
  // Hug the matches. A one-result search should not sit in a twelve-row card.
  readonly property int shownRows: root.apps.length === 0 ? 3 : Math.min(root.apps.length, root.visibleRows)
  readonly property int idealListHeight: rowHeight * shownRows
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int borderWidth: Math.max(1, Style.space(2))
  readonly property int cardWidth: Math.min(Style.space(440), Math.max(Style.space(280), panel.width - Style.space(48)))
  readonly property int idealCardHeight: contentMargin * 2 + borderWidth * 2 + Math.max(searchField.implicitHeight, Style.space(34)) + Style.spacing.md + idealListHeight
  readonly property int cardHeight: panel.height > Style.space(80) ? Math.min(idealCardHeight, panel.height - Style.space(48)) : idealCardHeight

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
    root.selectedIndex = AppList.moveIndex(root.selectedIndex, delta, root.apps.length)
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

  Component.onCompleted: root.viewReady = true

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

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "dtpietrzak-applist"

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
          if (root.menuEntry) root.menuEntry = null
          else if (!root.uninstallEntry) root.dismiss()
        }
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, root.borderWidth)
      padding: root.contentMargin

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
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Color.menu.scrim
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Style.font.menuFamily
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

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        TextField {
          id: searchField
          width: parent.width
          focus: true
          readOnly: !!root.menuEntry || !!root.uninstallEntry
          placeholderText: strings.t("search.placeholder")
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          foreground: Commons.Color.menu.text
          onTextChanged: if (text !== root.filterText) root.setFilter(text)
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleSearchKey(event) }
        }

        Item {
          width: parent.width
          height: Math.max(0, parent.height - searchField.height - parent.spacing)

          ListView {
            id: list
            anchors.fill: parent
            model: root.apps
            clip: true
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
                  ? angle / 120 * root.rowHeight * 6
                  : (pixels !== 0 ? pixels * 3 : angle / 120 * root.rowHeight * 6)
                if (delta === 0) return
                var bottom = list.originY + Math.max(0, list.contentHeight - list.height)
                list.contentY = Math.max(list.originY, Math.min(bottom, list.contentY - delta))
                event.accepted = true
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property var modelData
              readonly property bool selected: index === root.selectedIndex

              width: list.width
              height: root.rowHeight
              radius: Style.cornerRadius
              color: selected ? Commons.Color.menu.selectedBackground : "transparent"

              Image {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.controlPaddingX
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
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: root.appLibrary ? root.appLibrary.entryName(row.modelData) : ""
                color: row.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
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
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            visible: root.apps.length === 0
            text: root.filterText
              ? AppList.format(strings.t("list.empty"), AppList.plainLabel(root.filterText, 80))
              : strings.t("list.emptyAll")
            color: Commons.Color.menu.text
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }
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
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
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

            Text {
              id: menuLabel
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.controlPaddingX
              text: menuRow.modelData.label
              color: Commons.Color.popups.text
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
