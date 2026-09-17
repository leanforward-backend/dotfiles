#!/usr/bin/env bash
# Software-dim all Hyprland displays with hyprsunset's gamma control.
# The state is separate from the dotfiles so the slider can persist without
# making the repository dirty. Gamma and night-light temperature can coexist.
set -uo pipefail

action="${1:-get}"
requested="${2:-}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
state_file="$state_dir/extra-dim"

read_dim() {
  local value=0
  if [[ -r "$state_file" ]]; then
    read -r value < "$state_file"
  fi
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 0 || value > 80 )); then
    value=0
  fi
  printf '%s\n' "$value"
}

apply_dim() {
  local dim="$1"
  local gamma=$((100 - dim))

  if ! pgrep -x hyprsunset >/dev/null; then
    setsid uwsm-app -- hyprsunset >/dev/null 2>&1 &
    for _ in {1..20}; do
      [[ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.hyprsunset.sock" ]] && break
      sleep 0.05
    done
  fi

  if hyprctl hyprsunset gamma "$gamma" >/dev/null; then
    mkdir -p "$state_dir"
    printf '%s\n' "$dim" > "$state_file"
    printf '%s\n' "$dim"
    return 0
  fi

  return 1
}

case "$action" in
  get)
    read_dim
    ;;
  set)
    if [[ ! "$requested" =~ ^[0-9]+$ ]]; then
      printf 'usage: %s set <0-80>\n' "$0" >&2
      exit 2
    fi
    (( requested < 0 )) && requested=0
    (( requested > 80 )) && requested=80
    apply_dim "$requested"
    ;;
  restore)
    saved="$(read_dim)"
    if (( saved > 0 )); then
      apply_dim "$saved"
    else
      printf '0\n'
    fi
    ;;
  toggle)
    current="$(read_dim)"
    if (( current > 0 )); then
      apply_dim 0
    else
      apply_dim 50
    fi
    ;;
  *)
    printf 'usage: %s {get|set <0-80>|restore|toggle}\n' "$0" >&2
    exit 2
    ;;
esac
