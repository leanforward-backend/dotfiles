#!/bin/bash
# Media-key dispatcher with a pinned target.
#
# The bar widget (toby.media) writes a player name -- the tail of an MPRIS bus
# name, e.g. "spotify" or "chromium" -- to the pin file. While a pin is set and
# that player is on the bus, the media keys drive it directly over D-Bus.
# With no pin they drive the source that most recently started playing, which
# the widget records in the recent file. Only when neither resolves does
# everything fall through to omarchy's own media service, which picks whatever
# is playing.
#
# Seeking is the exception: omarchy's media service exposes no seek over IPC,
# so with neither set the seek actions find the playing player themselves.

set -u

PIN_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/media-target"
# Per login session on purpose: last session's player is no guide to this one.
RECENT_FILE="${XDG_RUNTIME_DIR:-/tmp}/toby-media-recent"
MPRIS_PREFIX="org.mpris.MediaPlayer2"
action="${1:-play-pause}"

read_pin() { [[ -f $PIN_FILE ]] && tr -d '[:space:]' <"$PIN_FILE"; }
read_recent() { [[ -f $RECENT_FILE ]] && tr -d '[:space:]' <"$RECENT_FILE"; }

# Bus names carry a per-process suffix for multi-instance players
# (org.mpris.MediaPlayer2.chromium.instance81932), so match on the stem.
find_bus() {
  local name="$1" quoted
  quoted=$(printf '%s' "$name" | sed 's/[][\.*^$(){}?+|\/]/\\&/g')
  busctl --user list --no-legend 2>/dev/null | awk '{print $1}' |
    grep -m1 -E "^${MPRIS_PREFIX//./\\.}\.${quoted}(\.instance[0-9]+)?$"
}

list_players() {
  busctl --user list --no-legend 2>/dev/null | awk '{print $1}' |
    grep -E "^${MPRIS_PREFIX//./\\.}\.[^.]+(\.instance[0-9]+)?$"
}

# Seek's own fallback target: the first player actually playing, which is what
# omarchy's media service would have picked anyway.
playing_bus() {
  local bus
  while read -r bus; do
    [[ -n $bus ]] || continue
    if [[ $(player_prop "$bus" org.mpris.MediaPlayer2.Player PlaybackStatus) == "Playing" ]]; then
      printf '%s' "$bus"
      return 0
    fi
  done < <(list_players)
  return 1
}

player_prop() {
  busctl --user get-property "$1" /org/mpris/MediaPlayer2 "$2" "$3" 2>/dev/null |
    cut -d'"' -f2
}

# Booleans come back unquoted ("b true"), so they need the last field, not the
# text between the quotes that player_prop pulls out of a string reply.
player_bool() {
  busctl --user get-property "$1" /org/mpris/MediaPlayer2 "$2" "$3" 2>/dev/null |
    awk '{print $NF}'
}

# Metadata comes back as one a{sv} line; the two fields seeking needs are
# unambiguous enough to pull out without a JSON parse on every key press.
track_meta() {
  busctl --user get-property "$1" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata 2>/dev/null
}

fallback() {
  case "$action" in
    play-pause) exec omarchy-shell media playPause ;;
    next) exec omarchy-shell media next ;;
    previous) exec omarchy-shell media previous ;;
    *) exit 1 ;;
  esac
}

# Chrome advertises CanSeek and then ignores relative Seek, so absolute
# SetPosition comes first and Seek is the fallback for players that report no
# position or track id (mpv's idle state, some web players).
seek_relative() {
  local bus="$1" delta="$2" meta pos track length target
  pos=$(busctl --user get-property "$bus" /org/mpris/MediaPlayer2 \
    org.mpris.MediaPlayer2.Player Position 2>/dev/null | awk '{print $NF}')
  meta=$(track_meta "$bus")
  track=$(printf '%s' "$meta" | grep -o '"mpris:trackid" o "[^"]*"' | cut -d'"' -f4)
  length=$(printf '%s' "$meta" | grep -o '"mpris:length" x [0-9]*' | awk '{print $NF}')

  if [[ -n $pos && -n $track ]]; then
    target=$((pos + delta))
    ((target < 0)) && target=0
    # Landing exactly on the end makes some players advance to the next track;
    # stop a second short of it.
    [[ -n $length ]] && ((length > 1000000 && target > length - 1000000)) &&
      target=$((length - 1000000))
    busctl --user call "$bus" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player \
      SetPosition ox "$track" "$target" >/dev/null 2>&1 && return 0
  fi

  # `--` keeps busctl from reading a negative offset as an option.
  busctl --user call -- "$bus" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player \
    Seek x "$delta" >/dev/null 2>&1
}

explicit_target=""

case "$action" in
  pin)
    [[ -n ${2:-} ]] || { echo "usage: media-keys.sh pin <player>" >&2; exit 1; }
    mkdir -p "$(dirname "$PIN_FILE")"
    printf '%s' "$2" >"$PIN_FILE"
    exit 0
    ;;
  unpin)
    rm -f "$PIN_FILE"
    exit 0
    ;;
  target)
    read_pin
    exit 0
    ;;
  cycle)
    # Pin the next source after the one the keys drive now, wrapping around.
    names=()
    while read -r bus; do
      [[ -n $bus ]] || continue
      name="${bus#"$MPRIS_PREFIX".}"
      names+=("${name%%.instance*}")
    done < <(list_players)
    ((${#names[@]} > 0)) || exit 0
    mapfile -t names < <(printf '%s\n' "${names[@]}" | sort -u)

    current=$(read_pin)
    [[ -n $current ]] || current=$(read_recent)
    next=0
    for i in "${!names[@]}"; do
      [[ ${names[i]} == "$current" ]] && next=$(((i + 1) % ${#names[@]}))
    done

    mkdir -p "$(dirname "$PIN_FILE")"
    printf '%s' "${names[next]}" >"$PIN_FILE"
    bus=$(find_bus "${names[next]}")
    identity=$(player_prop "$bus" org.mpris.MediaPlayer2 Identity)
    omarchy-shell -q osd show "{\"icon\":\"media\",\"message\":\"Media keys: ${identity:-${names[next]}}\"}"
    exit 0
    ;;
  recent)
    # With a player, record it; without one, print what is recorded.
    if [[ -n ${2:-} ]]; then
      printf '%s' "$2" >"$RECENT_FILE"
    else
      read_recent
    fi
    exit 0
    ;;
  play-pause | next | previous)
    explicit_target="${2:-}"
    ;;
  forward | back)
    seek_seconds="${2:-15}"
    explicit_target="${3:-}"
    ;;
  *)
    echo "usage: media-keys.sh [play-pause|next|previous] [player]" >&2
    echo "       media-keys.sh [forward|back] [seconds] [player]" >&2
    echo "       media-keys.sh [pin <player>|unpin|target|recent [player]]" >&2
    exit 1
    ;;
esac

# An explicit player (the bar widget's own row buttons) wins over the pin, and
# the pin wins over the most recent source. A pin whose player has gone away
# falls through to the recent one rather than straight to omarchy.
bus=""
for target in "$explicit_target" "$(read_pin)" "$(read_recent)"; do
  [[ -n $target ]] || continue
  bus=$(find_bus "$target") && [[ -n $bus ]] && break
done
[[ -n $bus ]] || target=""

if [[ -z $bus ]]; then
  # Seek has no service-side fallback to hand off to, so resolve a target here.
  case "$action" in
    forward | back) bus=$(playing_bus) || exit 0 ;;
    *) fallback ;;
  esac
fi

case "$action" in
  play-pause)
    method=PlayPause
    # Read the state before acting: reading it after races the player's own
    # property update, and the OSD would show the state we just left.
    if [[ $(player_prop "$bus" org.mpris.MediaPlayer2.Player PlaybackStatus) == "Playing" ]]; then
      icon=media-pause
    else
      icon=media-play
    fi
    ;;
  next)
    method=Next
    icon=media-next
    ;;
  previous)
    method=Previous
    icon=media-previous
    ;;
  forward)
    method=Seek
    icon=media-next
    ;;
  back)
    method=Seek
    icon=media-previous
    ;;
esac

identity=$(player_prop "$bus" org.mpris.MediaPlayer2 Identity)
[[ -n $identity ]] || identity="${target:-Media}"

if [[ $method == Seek ]]; then
  # A live stream reports CanSeek false and quietly ignores both seek calls,
  # so say so rather than let the OSD claim a jump that never happened.
  if [[ $(player_bool "$bus" org.mpris.MediaPlayer2.Player CanSeek) != "true" ]]; then
    omarchy-shell -q osd show "{\"icon\":\"media\",\"message\":\"$identity can't seek\"}"
    exit 0
  fi

  delta=$((seek_seconds * 1000000))
  [[ $action == back ]] && delta=$((-delta))
  seek_relative "$bus" "$delta"
  [[ $action == forward ]] && sign="+" || sign="-"
  omarchy-shell -q osd show "{\"icon\":\"$icon\",\"message\":\"$sign${seek_seconds}s  $identity\"}"
  exit 0
fi

busctl --user call "$bus" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player "$method" >/dev/null 2>&1 || fallback

omarchy-shell -q osd show "{\"icon\":\"$icon\",\"message\":\"$identity\"}"
