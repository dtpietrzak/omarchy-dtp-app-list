import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Where the start-menu overlays sit: in the screen corner next to the Omarchy
// menu button. Reads the bar edge and the button's section from shell.json,
// so moving the bar moves the overlays with it.
//
//   bar at the bottom -> bottom left      bar on the left  -> top left
//   bar at the top    -> top left         bar on the right -> top right
//
// A horizontal bar whose menu button sits in its right section uses the right
// corner instead.
QtObject {
  id: root

  property string position: "top"
  property bool buttonAtEnd: false

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barThickness: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  readonly property bool atBottom: position === "bottom"
  readonly property bool atRight: position === "right" || (!vertical && buttonAtEnd)

  // Distance from each screen edge. The bar's own edge also clears the bar.
  readonly property int marginTop: Style.gapsOut + (position === "top" ? barThickness : 0)
  readonly property int marginBottom: Style.gapsOut + (position === "bottom" ? barThickness : 0)
  readonly property int marginLeft: Style.gapsOut + (position === "left" ? barThickness : 0)
  readonly property int marginRight: Style.gapsOut + (position === "right" ? barThickness : 0)

  function cardX(areaWidth, cardWidth) {
    return atRight ? areaWidth - cardWidth - marginRight : marginLeft
  }
  function cardY(areaHeight, cardHeight) {
    return atBottom ? Math.max(marginTop, areaHeight - cardHeight - marginBottom) : marginTop
  }

  function hasButton(list) {
    if (!Array.isArray(list)) return false
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i] && list[i].id !== undefined ? list[i].id : list[i])
      if (/(^|\.)menu$/.test(id)) return true
    }
    return false
  }

  function load(text) {
    var bar = null
    try { bar = JSON.parse(text).bar } catch (e) { return }
    if (!bar) return
    var next = String(bar.position || "top")
    if (["top", "bottom", "left", "right"].indexOf(next) >= 0) position = next
    var layout = bar.layout || {}
    buttonAtEnd = !hasButton(layout.left) && !hasButton(layout.centerBegin)
      && (hasButton(layout.centerEnd) || hasButton(layout.right))
  }

  property var file: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.load(text())
    onFileChanged: reload()
  }
}
