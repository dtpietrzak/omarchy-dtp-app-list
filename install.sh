#!/usr/bin/env bash
# Install the list launcher and point the menu, Super+Alt+Space, and the dock
# apps button at it. Safe to run again: files that already match are left alone.
#
#   ./install.sh                  install from a checkout, or finish after plugin add
#   ./install.sh --patch-dock DIR patch one dock directory and nothing else

set -euo pipefail

PLUGIN_ID="dtpietrzak.applist"
ROOT="$(cd "$(dirname "$0")" && pwd)"
GLUE="$ROOT/glue"

fail() {
  echo "install: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: install.sh [--patch-dock DOCK_DIR]"
  exit 0
fi

patch_only=0
dock_dir=""
if [[ ${1:-} == "--patch-dock" ]]; then
  patch_only=1
  dock_dir="${2:-}"
  [[ -n $dock_dir && -d $dock_dir ]] || fail "--patch-dock needs a dock directory"
fi

sync_plugin() {
  local dest="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
  if [[ -d $dest ]] && [[ "$(realpath "$ROOT")" == "$(realpath "$dest")" ]]; then
    echo "Plugin files are already in $dest"
    return
  fi
  mkdir -p "$dest"
  local copied
  copied="$(rsync -a --checksum --delete --exclude .git --itemize-changes "$ROOT/" "$dest/")"
  if [[ -n $copied ]]; then
    echo "Synced plugin files to $dest"
  else
    echo "Plugin files already match $dest"
  fi
}

ensure_enabled() {
  local known=0 attempt
  for attempt in $(seq 1 40); do
    if omarchy plugin list --json | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null; then
      known=1
      break
    fi
    if [[ $attempt -eq 1 ]]; then
      omarchy-shell shell rescanPlugins >/dev/null
    fi
    sleep 0.05
  done
  [[ $known -eq 1 ]] || fail "plugin $PLUGIN_ID was not discovered"
  if omarchy plugin list --json | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null; then
    echo "Plugin $PLUGIN_ID is already enabled"
  else
    omarchy plugin enable "$PLUGIN_ID"
  fi
}

find_dock_id() {
  omarchy plugin list --json | jq -r --arg prefer "${USER}.dock" '
    [ .[] | select(.clonedFrom == "omarchy.dock") ] as $c
    | if ($c | length) == 0 then ""
      elif ($c | length) == 1 then $c[0].id
      else
        ($c | map(select(.id == $prefer)) | if length == 1 then .[0].id else "__ambiguous__" end)
      end
  '
}

ensure_dock_clone() {
  local dock_id
  dock_id="$(find_dock_id)"
  if [[ $dock_id == "__ambiguous__" ]]; then
    fail "more than one omarchy.dock clone is installed; keep ${USER}.dock or remove the extra one"
  fi
  if [[ -z $dock_id ]]; then
    omarchy plugin clone omarchy.dock
    dock_id="$(find_dock_id)"
    [[ -n $dock_id && $dock_id != "__ambiguous__" ]] || fail "cloning omarchy.dock did not leave a dock clone"
    echo "Cloned omarchy.dock to $dock_id"
  else
    echo "Dock clone $dock_id is already installed"
  fi
  dock_dir="$HOME/.config/omarchy/plugins/$dock_id"
  [[ -d $dock_dir ]] || fail "dock clone directory is missing: $dock_dir"
}

apply_edits() {
  python3 - "$GLUE" "$dock_dir" "$patch_only" <<'PY'
import json
import re
import sys
from pathlib import Path

glue = Path(sys.argv[1])
dock_dir = Path(sys.argv[2])
patch_only = sys.argv[3] == "1"
home = Path.home()

def read_snippet(name):
    return (glue / name).read_text()

def write_if_changed(path, text):
    path = Path(path)
    old = path.read_text() if path.exists() else None
    if old == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return True

def replace_block(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"install: {label} matched {count} times")
    return text.replace(old, new, 1)

dock_changed = False

def patch_dock_qml():
    global dock_changed
    path = dock_dir / "Dock.qml"
    text = path.read_text()
    original = text
    if "loadedDockConfig" not in text:
        text = replace_block(text, read_snippet("dock-props.old"), read_snippet("dock-props.new"), "Dock.qml config properties")
        text = replace_block(text, read_snippet("dock-config.old"), read_snippet("dock-config.new"), "Dock.qml config reader")
    elif "function dockFromConfigText" not in text:
        raise SystemExit("install: Dock.qml has loadedDockConfig but not the config reader")
    if 'toggle", "dtpietrzak.applist"' not in text:
        text = replace_block(text, read_snippet("dock-open.old"), read_snippet("dock-open.new"), "Dock.qml openApps()")
    if "function apps(): void { root.openApps() }" not in text:
        text = replace_block(text, read_snippet("dock-apps.old"), read_snippet("dock-apps.new"), "Dock.qml apps()")
    phrase = "a grid of every app"
    if phrase in text:
        text = text.replace(phrase, "a list of every app", 1)
    if text != original:
        path.write_text(text)
        dock_changed = True
        print("Updated Dock.qml")
    else:
        print("Dock.qml already opens the list")

def patch_dock_window():
    global dock_changed
    path = dock_dir / "DockWindow.qml"
    text = path.read_text()
    if "readonly property int dot:" in text:
        print("Dock button icon is already the list mark")
        return
    text = replace_block(text, read_snippet("dock-icon.old"), read_snippet("dock-icon.new"), "DockWindow.qml apps icon")
    path.write_text(text)
    dock_changed = True
    print("Updated the dock button icon")

def patch_manifest():
    global dock_changed
    path = dock_dir / "manifest.json"
    data = json.loads(path.read_text())
    kinds = list(data.get("kinds") or [])
    changed = False
    if "service" not in kinds:
        kinds.insert(0, "service")
        changed = True
    if "menu" not in kinds:
        kinds.append("menu")
        changed = True
    entry_points = dict(data.get("entryPoints") or {})
    if "service" not in entry_points:
        entry_points["service"] = "Dock.qml"
        changed = True
    if entry_points.get("menu") != "Menu.qml":
        entry_points["menu"] = "Menu.qml"
        changed = True
    if not changed:
        print("Dock manifest already exposes the menu entry")
        return
    data["kinds"] = kinds
    data["entryPoints"] = entry_points
    path.write_text(json.dumps(data, indent=2) + "\n")
    dock_changed = True
    print("Updated the dock manifest")

def patch_menu_qml():
    global dock_changed
    path = dock_dir / "Menu.qml"
    if write_if_changed(path, read_snippet("dock-menu.snippet")):
        dock_changed = True
        print("Added the dormant dock Menu.qml")
    else:
        print("Dormant dock Menu.qml is already in place")

def upsert_menu():
    path = home / ".config/omarchy/extensions/omarchy-menu.jsonc"
    if not path.exists():
        template = Path("/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc")
        omarchy = __import__("os").environ.get("OMARCHY_PATH", "")
        if omarchy:
            candidate = Path(omarchy) / "config/omarchy/extensions/omarchy-menu.jsonc"
            if candidate.is_file():
                template = candidate
        path.write_text(template.read_text())
    desired = {
        "icon": "\uf03a",
        "label": "Apps",
        "aliases": ["app", "applications"],
        "provider": "apps",
        "action": "omarchy-shell shell summon dtpietrzak.applist",
    }
    lines = path.read_text().splitlines()
    hits = []
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        if re.search(r'"apps"\s*:', line):
            hits.append(index)
    if len(hits) > 1:
        raise SystemExit("install: omarchy-menu.jsonc has more than one apps key")
    body = json.dumps(desired, ensure_ascii=False, separators=(",", ":"))
    rendered = f'  "apps": {body}'
    if len(hits) == 1:
        line = lines[hits[0]]
        start = line.index("{")
        end = line.rindex("}")
        if json.loads(line[start:end + 1]) == desired:
            print("Menu Apps row already opens the list")
            return
        comma = "," if line.rstrip().endswith(",") else ""
        lines[hits[0]] = rendered + comma
    else:
        close = None
        for index in range(len(lines) - 1, -1, -1):
            if lines[index].strip() == "}":
                close = index
                break
        if close is None:
            raise SystemExit("install: omarchy-menu.jsonc has no closing brace")
        previous = close - 1
        while previous >= 0 and (lines[previous].strip() == "" or lines[previous].lstrip().startswith("//")):
            previous -= 1
        if previous >= 0 and lines[previous].strip() not in ("{",) and not lines[previous].rstrip().endswith(","):
            lines[previous] = lines[previous].rstrip() + ","
        lines.insert(close, rendered)
    text = "\n".join(lines)
    if path.read_text().endswith("\n"):
        text += "\n"
    elif not text.endswith("\n"):
        text += "\n"
    path.write_text(text)
    print("Updated the menu Apps row")

def ensure_line(path, pattern, addition, label):
    text = path.read_text()
    if len(re.findall(pattern, text)) > 1:
        raise SystemExit(f"install: {label} appears more than once in {path}")
    if re.search(pattern, text):
        print(f"{label} is already set")
        return False
    if text and not text.endswith("\n"):
        text += "\n"
    text += addition
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text)
    print(f"Updated {label}")
    return True

patch_dock_qml()
patch_dock_window()
patch_manifest()
patch_menu_qml()
hypr_changed = False
if not patch_only:
    upsert_menu()
    bindings = home / ".config/hypr/bindings.lua"
    hyprland = home / ".config/hypr/hyprland.lua"
    if not bindings.is_file() or not hyprland.is_file():
        raise SystemExit("install: ~/.config/hypr/bindings.lua and hyprland.lua must already exist")
    bind = 'o.rebind("SUPER + ALT + SPACE", "Apps", { panel = "dtpietrzak.applist" })\n'
    bind_pattern = r'o\.rebind\(\s*"SUPER \+ ALT \+ SPACE"\s*,\s*"Apps"\s*,\s*\{\s*panel\s*=\s*"dtpietrzak\.applist"\s*\}\s*\)'
    if ensure_line(
        bindings,
        bind_pattern,
        "\n-- App launcher. Super+Alt+Space used to open the icon grid.\n" + bind,
        "Super+Alt+Space",
    ):
        hypr_changed = True
    rule = 'hl.layer_rule({ match = { namespace = "^dtpietrzak-applist$" }, no_anim = true, animation = "none" })\n'
    rule_pattern = r'hl\.layer_rule\(\s*\{\s*match\s*=\s*\{\s*namespace\s*=\s*"\^dtpietrzak-applist\$"\s*\}\s*,\s*no_anim\s*=\s*true\s*,\s*animation\s*=\s*"none"\s*\}\s*\)'
    if ensure_line(
        hyprland,
        rule_pattern,
        "\n-- App list launcher: pop in without a compositor fade, like the other shell overlays.\n" + rule,
        "App list layer rule",
    ):
        hypr_changed = True
print(f"STATUS hypr_changed={1 if hypr_changed else 0}")
print(f"STATUS dock_changed={1 if dock_changed else 0}")
PY
}

if [[ $patch_only -eq 1 ]]; then
  apply_edits
  exit 0
fi

sync_plugin
ensure_enabled
ensure_dock_clone
status="$(apply_edits)"
printf '%s\n' "$status"

hypr_changed=0
dock_changed=0
if grep -q '^STATUS hypr_changed=1$' <<<"$status"; then
  hypr_changed=1
fi
if grep -q '^STATUS dock_changed=1$' <<<"$status"; then
  dock_changed=1
fi

hyprctl reload >/dev/null
errors="$(hyprctl configerrors 2>&1 || true)"
if [[ -n ${errors//[[:space:]]/} ]]; then
  printf '%s\n' "$errors" >&2
  fail "Hyprland reported config errors"
fi
if [[ $hypr_changed -eq 1 ]]; then
  echo "Hyprland config reloaded with no errors"
else
  echo "Hyprland config has no errors"
fi

if [[ $dock_changed -eq 1 ]]; then
  echo "Dock files changed. Restarting the shell so the apps button picks them up."
  omarchy restart shell
else
  echo "Dock files were already patched, so the shell was left running"
fi
