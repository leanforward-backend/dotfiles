-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Move the focused scratchpad window back to the current workspace.
o.bind("SUPER + SHIFT + ALT + S", "Move window out of scratchpad",
  hl.dsp.window.move({ workspace = "+0" }))

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- No physical Print key on this keyboard, so screenshot moves to SUPER+SHIFT+S
-- (this overrides the default Google Maps webapp shortcut on that key).
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")

-- Ctrl+V pastes text and images. foot passes Ctrl+V through raw (foot's paste
-- is text-only), so in terminals terminal-paste picks: text on the clipboard ->
-- Shift+Insert (terminal paste), image only -> raw Ctrl+V for Claude Code.
-- Other windows get Ctrl+V re-sent unchanged; synthetic keys skip binds.
local function send_key_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function active_window_is_terminal()
  local window = hl.get_active_window()
  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

o.bind("CTRL + V", "Paste", function()
  if active_window_is_terminal() then
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/terminal-paste")
  else
    send_key_once("CTRL", "V")
  end
end)

-- Volume keys step by 2% instead of the default 5%.
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
o.bind("XF86AudioRaiseVolume", "Volume up", "omarchy-audio-output-volume +2", { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Volume down", "omarchy-audio-output-volume -2", { locked = true, repeating = true })

-- Media keys go through the toby.media bar widget's pin: while a source is
-- pinned there they drive that player over MPRIS, otherwise the script hands
-- off to omarchy-shell and the default "whatever is playing" behaviour.
-- SHIFT + Play/Pause still cycles the source through omarchy's media service.
local media_keys = "~/.config/omarchy/plugins/toby.media/media-keys.sh"
hl.unbind("XF86AudioPlay")
hl.unbind("XF86AudioPause")
hl.unbind("XF86AudioNext")
hl.unbind("XF86AudioPrev")
hl.unbind("ALT + XF86AudioPlay")
hl.unbind("ALT + SHIFT + XF86AudioPlay")
o.bind("XF86AudioPlay", "Play/pause", media_keys .. " play-pause", { locked = true })
o.bind("XF86AudioPause", "Play/pause", media_keys .. " play-pause", { locked = true })
o.bind("XF86AudioNext", "Next track", media_keys .. " next", { locked = true })
o.bind("XF86AudioPrev", "Previous track", media_keys .. " previous", { locked = true })
o.bind("ALT + XF86AudioPlay", "Next track", media_keys .. " next", { locked = true })
o.bind("ALT + SHIFT + XF86AudioPlay", "Previous track", media_keys .. " previous", { locked = true })

-- Scrub the current source by 15s. SHIFT + next/prev were free; SHIFT +
-- play/pause stays on omarchy's "switch media source".
o.bind("SHIFT + XF86AudioNext", "Forward 15s", media_keys .. " forward 15", { locked = true, repeating = true })
o.bind("SHIFT + XF86AudioPrev", "Back 15s", media_keys .. " back 15", { locked = true, repeating = true })
