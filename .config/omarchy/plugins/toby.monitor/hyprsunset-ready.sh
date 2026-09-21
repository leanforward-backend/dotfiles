#!/usr/bin/env bash
# Make sure hyprsunset is running AND that its IPC socket actually answers.
#
# Three things start hyprsunset on this machine: the omarchy shell's nightlight
# service, nightlight-schedule.sh and extra-dim.sh. Each used to carry its own
# `pgrep -x hyprsunset || setsid uwsm-app -- hyprsunset` block. When two of them
# fire in the same second - which is exactly what happens at login, when the
# schedule's Persistent=true catch-up run lands while the shell is still
# starting - they race. The loser replaces the winner's socket file and exits,
# leaving a listener that nothing can reach by path. Every `hyprctl hyprsunset`
# call then fails with exit 3 until the next reboot, which takes out night light
# and extra dim together.
#
# So this helper takes a lock, probes the socket instead of trusting pgrep, and
# repairs a dead socket rather than stacking another instance on top of it.
set -uo pipefail

runtime="${XDG_RUNTIME_DIR:-/run/user/$UID}"
lock_file="$runtime/hyprsunset-ready.lock"

# systemd units get no session env, so find the compositor before using hyprctl.
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  sig=$(ls -t "$runtime/hypr" 2>/dev/null | head -n1)
  [[ -n "$sig" ]] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
fi
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
export PATH="$OMARCHY_PATH/bin:$PATH"

socket_path() {
  printf '%s/hypr/%s/.hyprsunset.sock' "$runtime" "${HYPRLAND_INSTANCE_SIGNATURE:-}"
}

# The only check that proves the socket is usable is talking to it. Testing for
# the file with -S is what let the stale socket go unnoticed for a whole evening.
responds() {
  hyprctl hyprsunset temperature >/dev/null 2>&1
}

wait_for_response() {
  local tries="$1"
  for ((i = 0; i < tries; i++)); do
    responds && return 0
    sleep 0.25
  done
  return 1
}

# A fresh hyprsunset comes up at gamma 100, so a repair silently throws away
# the extra dim. Put it back from the saved state rather than leaving the
# screen brighter than the user set it. Applied here, with hyprctl directly,
# so extra-dim.sh never has to call back into this script.
restore_dim() {
  local state_file="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/extra-dim"
  local dim=0
  [[ -r "$state_file" ]] && read -r dim < "$state_file"
  [[ "$dim" =~ ^[0-9]+$ ]] || return 0
  ((dim > 0 && dim <= 80)) || return 0
  hyprctl hyprsunset gamma "$((100 - dim))" >/dev/null 2>&1
}

ensure() {
  responds && return 0

  # An instance that is still booting only needs a moment; don't kill it.
  if pgrep -x hyprsunset >/dev/null; then
    wait_for_response 20 && return 0
  fi

  # Unreachable for real: nothing running, or a race left a socket file with no
  # listener behind it. Clear both cases out before starting a clean instance.
  pkill -x hyprsunset 2>/dev/null
  for ((i = 0; i < 20; i++)); do
    pgrep -x hyprsunset >/dev/null || break
    sleep 0.1
  done
  rm -f "$(socket_path)"

  # 9>&- matters: without it hyprsunset inherits the lock fd and keeps the lock
  # held for as long as it runs, so the next caller blocks here forever.
  setsid uwsm-app -- hyprsunset >/dev/null 2>&1 9>&- &
  wait_for_response 40 || return 1
  restore_dim
}

# Serialise against the other script, so the two of us can never race each other.
exec 9>"$lock_file"
# Bounded: blocking the caller forever is worse than missing one dim step.
if ! flock -w 30 9; then
  printf 'hyprsunset-ready: timed out waiting for %s\n' "$lock_file" >&2
  exit 1
fi
ensure
