#!/bin/bash
# Rebuilds this cloned menu from Omarchy's packaged omarchy.menu plus
# customizations.patch, so the clone tracks upstream instead of rotting.
# A frozen copy of Menu.qml went black in 4.0.6 when upstream moved the Color
# singleton under qs.Commons; regenerating from the stock files avoids that.
#
#   rebuild.sh          # rebuild; restart the shell only if a file changed
#   rebuild.sh --save   # after editing Menu.qml by hand, record the edits
#                       # into customizations.patch
#
# Run by the post-update and post-boot hooks. Menu.qml, MenuModel.js and
# BarWidget.qml are generated and gitignored; edit them, then --save.
#
# If the patch stops applying, the stock menu is installed unpatched (working,
# just without the customizations) and a critical notification says so.
set -euo pipefail

dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
stock="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/menu"
patch_file="$dir/customizations.patch"
files=(Menu.qml MenuModel.js BarWidget.qml)

if [[ ${1:-} == --save ]]; then
  diff -u --label a/Menu.qml --label b/Menu.qml "$stock/Menu.qml" "$dir/Menu.qml" >"$patch_file" || true
  echo "saved $(grep -c '^@@' "$patch_file") hunk(s) to $patch_file"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for f in "${files[@]}"; do cp "$stock/$f" "$tmp/$f"; done

if ! patch -s --no-backup-if-mismatch -r - "$tmp/Menu.qml" "$patch_file" >/dev/null 2>&1; then
  cp "$stock/Menu.qml" "$tmp/Menu.qml"
  omarchy-notification-send -u critical "Menu customizations not applied" \
    "customizations.patch no longer applies to Omarchy's menu, so the stock menu is in use. Re-apply the edits to $dir/Menu.qml and run rebuild.sh --save." || true
fi

changed=0
for f in "${files[@]}"; do
  if ! cmp -s "$tmp/$f" "$dir/$f"; then
    cp "$tmp/$f" "$dir/$f"
    changed=1
  fi
done

# The shell's hot-reload keeps serving a cached compile of the old Menu.qml,
# so a real restart is needed for the new file to take effect.
if ((changed)) && pgrep -x quickshell >/dev/null; then
  omarchy restart shell >/dev/null 2>&1 || true
fi
