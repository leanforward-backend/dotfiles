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

  # Shared with nightlight-schedule.sh: takes a lock, proves the socket answers,
  # and repairs a dead one. Never start hyprsunset from here directly.
  if ! "$(dirname "$(readlink -f "$0")")/hyprsunset-ready.sh"; then
    printf 'extra-dim: hyprsunset is not reachable\n' >&2
    return 1
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
