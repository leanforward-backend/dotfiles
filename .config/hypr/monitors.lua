-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Scale last picked for an output in the display panel (or with
-- omarchy-hyprland-monitor-scaling), read back from that tool's change log so
-- the choice survives reloads; `default` applies until one is picked.
-- Keep the rules below calling this rather than using a plain number: Omarchy's
-- clamshell watcher re-applies a plain laptop scale every 2s while docked, which
-- snaps panel changes on eDP-1 straight back.
local function panel_scale(output, default)
  local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
  local log = io.open(state .. "/omarchy/monitor-scaling.log", "r")
  if not log then return default end

  local scale = default
  for line in log:lines() do
    local value, name = line:match("\tnew=([%d.]+)\tmonitor=([^\t]+)")
    local parsed = tonumber(value)
    if name == output and parsed and parsed >= 0.25 and parsed <= 4 then scale = parsed end
  end
  log:close()
  return scale
end

-- Laptop panel on the left, external monitor on the right (matches physical desk layout).
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = panel_scale("eDP-1", 1.6) })
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto-right", scale = panel_scale("HDMI-A-1", 1) })

-- Unity Editor has no internal UI scaling on Linux, so its size follows this
-- monitor's scale. Drop below 1 to shrink everything on this screen:
-- 0.8 gives a 4300x1800 logical grid (both integers, so no fractional blur).
-- hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto-right", scale = 0.8 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
