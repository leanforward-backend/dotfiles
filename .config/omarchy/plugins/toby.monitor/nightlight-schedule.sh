#!/usr/bin/env bash
# Night light schedule for the Display panel.
#
# A systemd user timer (nightlight-schedule.timer) fires at ON_TIME and
# OFF_TIME and runs `apply`, which sets the night light to whatever the
# current time of day calls for. `apply` is idempotent, so a timer that
# elapsed during suspend or shutdown catches up harmlessly on resume/login.
set -uo pipefail

ON_TIME="20:30"   # night light turns on
OFF_TIME="07:00"  # night light turns off

action="${1:-status}"
timer="nightlight-schedule.timer"

# Whether a HH:MM lies inside the [ON_TIME, OFF_TIME) window that wraps midnight.
in_night_window() {
  local now="$1"
  if [[ "$ON_TIME" > "$OFF_TIME" ]]; then
    [[ "$now" > "$ON_TIME" || "$now" == "$ON_TIME" || "$now" < "$OFF_TIME" ]]
  else
    [[ ( "$now" > "$ON_TIME" || "$now" == "$ON_TIME" ) && "$now" < "$OFF_TIME" ]]
  fi
}

# Systemd units have no session env when started from a TTY-less context, so
# make sure hyprctl and qs can find their sockets.
ensure_session_env() {
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    local sig
    sig=$(ls -t "$runtime/hypr" 2>/dev/null | head -n1)
    [[ -n "$sig" ]] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
  fi
  export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
  export PATH="$OMARCHY_PATH/bin:$PATH"
}

set_nightlight() {
  local want="$1"  # enable | disable
  ensure_session_env
  # Already in the wanted state? Leave it alone so a manually chosen
  # strength (temperature) survives the 20:30 tick.
  local current
  current=$(omarchy-shell nightlight status 2>/dev/null || true)
  case "$want:$current" in
    enable:*'"enabled":true'*|disable:*'"enabled":false'*) return 0 ;;
  esac
  # Prefer the shell service so the bar indicator and panel update at once.
  if omarchy-shell nightlight "$want" >/dev/null 2>&1; then
    return 0
  fi
  # Shell not running: drive hyprsunset directly with the same temperatures.
  local temp=6500
  [[ "$want" == "enable" ]] && temp=4000
  if ! pgrep -x hyprsunset >/dev/null; then
    setsid uwsm-app -- hyprsunset >/dev/null 2>&1 &
    sleep 1
  fi
  hyprctl hyprsunset temperature "$temp" >/dev/null 2>&1
}

enabled() {
  systemctl --user is-enabled --quiet "$timer" 2>/dev/null
}

status_json() {
  local on=false
  enabled && on=true
  printf '{"enabled":%s,"on":"%s","off":"%s"}\n' "$on" "$ON_TIME" "$OFF_TIME"
}

case "$action" in
  status)
    status_json
    ;;
  enable)
    systemctl --user daemon-reload
    systemctl --user enable --now "$timer" >/dev/null 2>&1
    status_json
    ;;
  disable)
    systemctl --user disable --now "$timer" >/dev/null 2>&1
    status_json
    ;;
  toggle)
    if enabled; then "$0" disable; else "$0" enable; fi
    ;;
  apply)
    if in_night_window "$(date +%H:%M)"; then
      set_nightlight enable
    else
      set_nightlight disable
    fi
    ;;
  *)
    printf 'usage: %s {status|enable|disable|toggle|apply}\n' "$0" >&2
    exit 2
    ;;
esac
