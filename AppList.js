// Pure helpers for the list launcher. Launch keeps the desktop id as Quickshell
// reports it: gtk-launch needs the ".desktop" suffix appended, and an id such
// as org.telegram.desktop already ends in those letters. Pin checks strip one
// trailing file suffix on both sides so they still match the dock's saved pins.

function desktopId(value) {
  var id = String(value == null ? "" : value).trim()
  if (!id || id.length > 256) return ""
  if (/[\0\r\n]/.test(id)) return ""
  return id
}

function normalizeDesktopId(value) {
  var id = desktopId(value)
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function pinnedMap(config) {
  var next = ({})
  var dock = config && config.dock
  var pins = dock && Array.isArray(dock.pinned) ? dock.pinned : []
  var limit = Math.min(pins.length, 200)
  for (var i = 0; i < limit; i++) {
    var id = normalizeDesktopId(pins[i])
    if (id) next[id] = true
  }
  return next
}

function closestIndex(count) {
  return count > 0 ? 0 : -1
}

function moveIndex(index, delta, count) {
  if (count <= 0) return -1
  var start = index < 0 ? 0 : index
  return Math.max(0, Math.min(count - 1, start + delta))
}

// Display text stays literal. Callers put it in a PlainText field, so markup
// shaped like "<img src='https://example.invalid/tracker'>" is shown as text.
function plainLabel(value, limit) {
  var cap = limit > 0 ? limit : 120
  var text = String(value == null ? "" : value)
  if (text.length > cap) return text.slice(0, cap) + "…"
  return text
}

function format(template, value) {
  return String(template == null ? "" : template).split("%1").join(String(value == null ? "" : value))
}

if (typeof module !== "undefined") {
  module.exports = {
    desktopId: desktopId,
    normalizeDesktopId: normalizeDesktopId,
    pinnedMap: pinnedMap,
    closestIndex: closestIndex,
    moveIndex: moveIndex,
    plainLabel: plainLabel,
    format: format
  }
}
