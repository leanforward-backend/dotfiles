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
    tmp="$(mktemp)" || exit 1
    {
      echo "# Read by /usr/bin/spotify at launch (one flag per line, # for comments)."
      echo "# The scale line is rewritten by the UI Scale bar widget."
      echo "--force-device-scale-factor=$scale"
    } > "$tmp"
    mv "$tmp" "$conf" || exit 1

    pkill -f '^/opt/spotify/spotify' 2>/dev/null
    sleep 1
    hyprctl dispatch 'hl.dsp.exec_cmd("spotify")' >/dev/null 2>&1
    echo "  spotify restarted at $scale" >> "$log"
    ;;
  *)
    echo "  ERROR: unknown app '$app'" >> "$log"
    exit 1
    ;;
esac
