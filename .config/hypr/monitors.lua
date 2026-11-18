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

local function hostname()
  local f = io.open("/etc/hostname", "r")
  if not f then return "" end
  local name = f:read("*l") or ""
  f:close()
  return name
end

if hostname() == "s" then
  -- Desktop "s" (RTX 5080; the i7-14700KF has no iGPU, so motherboard video ports are dead).
  -- Matched by description so the rules follow the screens whichever GPU port they're on.
  local lg = "desc:LG Electronics LG HDR 4K 201NTHM8E737"
  local side = "desc:XXX AAA" -- 1080p touch screen on the left, rotated to portrait (1080x1920)
  -- transform: 1 = 90°, 3 = 270°. 1 was upside down on this desk.
  hl.monitor({ output = side, mode = "1920x1080@60", position = "0x0", scale = 1, transform = 3 })
  hl.monitor({ output = lg, mode = "3840x2160@60", position = "1080x0", scale = panel_scale("DP-2", 1) })
  hl.workspace_rule({ workspace = "1", monitor = lg, default = true })
  -- The side screen's touch panel (USB). Pin it to that screen. Touch does NOT inherit the
  -- monitor's rotation: without transform = 3 every tap lands one corner clockwise off.
  hl.device({ name = "ilitek-multi-touch-v5103", output = "HDMI-A-1", transform = 3 })
else
  -- Laptop panel on the left, external monitor on the right (matches physical desk layout).
  hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = panel_scale("eDP-1", 1.6) })
  hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto-right", scale = panel_scale("HDMI-A-1", 1) })
end

-- Unity Editor has no internal UI scaling on Linux, so its size follows this
-- monitor's scale. Drop below 1 to shrink everything on this screen:
-- 0.8 gives a 4300x1800 logical grid (both integers, so no fractional blur).
-- hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto-right", scale = 0.8 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
