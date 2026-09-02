#!/usr/bin/env bash
# Sets an app's internal UI scale -- how big everything drawn INSIDE its
# window is -- and restarts it so the change takes effect.
#
# Chromium/Electron reads --force-device-scale-factor at startup only, so
# applying a new value always means relaunching the app.
#
# Usage: set-scale.sh spotify 0.8
set -uo pipefail

app="${1:-}"
scale="${2:-}"
log="${XDG_RUNTIME_DIR:-/tmp}/toby-ui-scale.log"

echo "$(date '+%H:%M:%S') set-scale app=$app scale=$scale" >> "$log"

if [ -z "$app" ] || [ -z "$scale" ]; then
  echo "  ERROR: usage: set-scale.sh <app> <scale>" >> "$log"
  exit 1
fi

case "$app" in
  spotify)
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/spotify-flags.conf"
    # Written in place, NOT via a temp file and mv. This path is a symlink into
    # the dotfiles repo, and mv would replace the link with a regular file --
    # silently detaching the config from version control on every change.
    {
      echo "# Read by /usr/bin/spotify at launch (one flag per line, # for comments)."
      echo "# The scale line is rewritten by the UI Scale bar widget."
      echo "--force-device-scale-factor=$scale"
    } > "$conf" || exit 1

    pkill -f '^/opt/spotify/spotify' 2>/dev/null
    sleep 1
    hyprctl dispatch 'hl.dsp.exec_cmd("spotify")' >/dev/null 2>&1
    echo "  spotify restarted at $scale" >> "$log"
    ;;
  unity)
    # Unity's editor takes its UI scale from the GTK scale factor, which is
    # GDK_SCALE -- an integer, so only 1 or 2. Unity Hub passes its own value
    # down to every editor it spawns, so this is read by ~/.local/bin/unity-hub
    # at Hub launch (and by ~/.local/bin/unity-editor for direct launches).
    #
    # Deliberately does NOT restart Hub: that also closes any open editor,
    # which would cost unsaved work. Takes effect next time Hub starts.
    case "$scale" in
      1|2) ;;
      *) echo "  ERROR: unity scale must be 1 or 2, got '$scale'" >> "$log"; exit 1 ;;
    esac
    echo "$scale" > "${XDG_CONFIG_HOME:-$HOME/.config}/unity-ui-scale"
    echo "  unity scale set to $scale (applies when Hub next starts)" >> "$log"
    ;;
  *)
    echo "  ERROR: unknown app '$app'" >> "$log"
    exit 1
    ;;
esac
