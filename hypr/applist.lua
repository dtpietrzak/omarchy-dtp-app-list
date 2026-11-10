-- Blur behind the app list card when the bar is glassy. The card's background
-- follows the bar's, so it needs the same blur. AppList.qml runs this file when
-- it starts and after every Hyprland reload, which forgets layer rules. Omarchy
-- reloads Hyprland whenever the glassy toggle file comes or goes.
local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local glassy = io.open(state_home .. "/omarchy/toggles/hypr/bar-glassy.lua")
if glassy then
  glassy:close()
  hl.layer_rule({ match = { namespace = "^dtpietrzak-applist$" }, blur = true, ignore_alpha = 0.3 })
end
