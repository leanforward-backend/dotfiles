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

# omarchy treats anything below IDENTITY_TEMP as "night light on"; matching it
# keeps this script, the bar indicator and `omarchy toggle nightlight` agreed.
IDENTITY_TEMP=6000
NIGHT_TEMP=4000
DAY_TEMP=6500

helper() {
  "$(dirname "$(readlink -f "$0")")/hyprsunset-ready.sh"
}

# Read the temperature from hyprsunset itself. The shell caches its own idea of
# the state, and that cache is wrong for as long as it takes to notice a
# hyprsunset restart, which is exactly when this script runs at login.
current_temp() {
  hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1
}

set_nightlight() {
  local want="$1"  # enable | disable
  ensure_session_env

  # Shared with extra-dim.sh: takes a lock, proves the socket answers, and
  # repairs a dead one. Never start hyprsunset from here directly.
  if ! helper; then
    printf 'nightlight: hyprsunset is not reachable\n' >&2
    return 1
  fi

  local target=$DAY_TEMP
  [[ "$want" == "enable" ]] && target=$NIGHT_TEMP

  # Already in the wanted state? Leave it alone, so a manually chosen strength
  # survives the 20:30 tick.
  local current
  current=$(current_temp)
  if [[ -n "$current" ]]; then
    if [[ "$want" == "enable" && "$current" -lt "$IDENTITY_TEMP" ]]; then return 0; fi
    if [[ "$want" == "disable" && "$current" -ge "$IDENTITY_TEMP" ]]; then return 0; fi
  fi

  # Prefer the shell so the bar indicator and panel update at once.
  omarchy-shell nightlight "$want" >/dev/null 2>&1

  # Then confirm against hyprsunset and resend if it did not land. A freshly
  # started hyprsunset applies its own default at the end of its boot, which
  # clobbers anything set before then.
  local i
  for ((i = 0; i < 10; i++)); do
    current=$(current_temp)
    if [[ -n "$current" ]]; then
      if [[ "$want" == "enable" && "$current" -lt "$IDENTITY_TEMP" ]]; then break; fi
      if [[ "$want" == "disable" && "$current" -ge "$IDENTITY_TEMP" ]]; then break; fi
    fi
    hyprctl hyprsunset temperature "$target" >/dev/null 2>&1
    sleep 0.2
  done

  # Let the bar catch up with whatever we just did directly.
  omarchy-shell -q nightlight refresh >/dev/null 2>&1

  current=$(current_temp)
  [[ -n "$current" ]] || return 1
  if [[ "$want" == "enable" ]]; then
    [[ "$current" -lt "$IDENTITY_TEMP" ]]
  else
    [[ "$current" -ge "$IDENTITY_TEMP" ]]
  fi
}

# The catch-up run fires the moment the timer starts at login, which can be
# seconds before the shell is answering IPC. Waiting for it keeps us off the
# fallback path, and off a hyprsunset launch that races the shell's own.
wait_for_shell() {
  local deadline=$((SECONDS + ${1:-90}))
  while ((SECONDS < deadline)); do
    omarchy-shell nightlight status >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
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
    ensure_session_env
    wait_for_shell 90 || true
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
