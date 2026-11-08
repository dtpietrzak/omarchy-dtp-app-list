# omarchy-dtp-app-list

List launcher for Omarchy. One row per app, a search field on the top line, and the theme's right-click menu.

The shell plugin id is `dtpietrzak.applist`. The git repository name is `omarchy-dtp-app-list`.

## Install

From a git URL, Omarchy clones this repo into the plugin directory. That does not wire up the key, the menu, or the dock button, so run the script after it:

```bash
omarchy plugin add <git-url> --enable
~/.config/omarchy/plugins/dtpietrzak.applist/install.sh
```

From a local checkout:

```bash
./install.sh
```

The script copies the plugin into `~/.config/omarchy/plugins/dtpietrzak.applist` when it is run from a checkout, enables it, and then:

- points the Omarchy menu Apps row at the list
- rebinds Super+Alt+Space to the list
- adds a Hyprland layer rule so the list does not fade in
- clones `omarchy.dock` when this machine does not already have a clone, then points that clone's apps button at the list

The clone's id is `<username>.dock`. The script finds it by `clonedFrom`, so it is not tied to one username. Running it again leaves anything that already matches untouched. It does not copy monitors, touchpad settings, pinned apps, or `shell.json`.

The dock button lives on that personal clone. Later Omarchy dock updates do not apply to the clone until it is removed and this script is run again, which clones a fresh dock and reapplies the patch.

## Check

```bash
node tests/applist.test.js
omarchy plugin validate .
```
