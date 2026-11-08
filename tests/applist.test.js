const assert = require("assert")
const fs = require("fs")
const path = require("path")
const AppList = require("../AppList.js")

const markup = "<img src=\"https://example.invalid/tracker\">"

assert.strictEqual(AppList.plainLabel(markup, 200), markup)
assert.strictEqual(
  AppList.format("No apps match “%1”", markup),
  "No apps match “" + markup + "”"
)
assert.strictEqual(
  AppList.format("Do you want to uninstall %1?", "%1 %2"),
  "Do you want to uninstall %1 %2?"
)
assert.strictEqual(AppList.plainLabel("abcdef", 4), "abcd…")

assert.strictEqual(AppList.desktopId("org.telegram.desktop"), "org.telegram.desktop")
assert.strictEqual(AppList.desktopId("bad\nid"), "")
assert.strictEqual(AppList.normalizeDesktopId("chromium.desktop"), "chromium")
assert.strictEqual(AppList.normalizeDesktopId("org.telegram.desktop"), "org.telegram")

const pins = AppList.pinnedMap({
  dock: { pinned: ["chromium.desktop", "org.gnome.Nautilus", "bad\nid", ""] }
})
assert.strictEqual(pins.chromium, true)
assert.strictEqual(pins["org.gnome.Nautilus"], true)
assert.strictEqual(pins["bad\nid"], undefined)
assert.strictEqual(Object.keys(pins).length, 2)

assert.strictEqual(AppList.closestIndex(0), -1)
assert.strictEqual(AppList.closestIndex(4), 0)
assert.strictEqual(AppList.moveIndex(-1, 0, 3), 0)
assert.strictEqual(AppList.moveIndex(10, 0, 3), 2)
assert.strictEqual(AppList.moveIndex(1, 1, 3), 2)
assert.strictEqual(AppList.moveIndex(0, -1, 3), 0)

const qml = fs.readFileSync(path.join(__dirname, "../AppList.qml"), "utf8")
const textBlocks = qml.split(/Text\s*\{/).slice(1)
assert.ok(textBlocks.length >= 3, "expected Text elements")
for (let i = 0; i < textBlocks.length; i++) {
  const body = textBlocks[i].split("}")[0]
  assert.ok(
    /textFormat:\s*Text\.PlainText/.test(body),
    "Text element " + i + " is missing textFormat: Text.PlainText"
  )
}

console.log("applist tests ok")
