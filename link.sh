#!/usr/bin/env bash
# Symlinks every tracked file in this repo to the matching path under $HOME.
#
# The repo holds the real files; $HOME gets symlinks pointing at them. That is
# what makes `git pull` take effect immediately -- the live config and the repo
# are the same file. Run this after cloning on a new machine, and again after a
# pull that introduces files this machine has never linked before.
#
#   ./link.sh --dry-run   # show what would change, touch nothing
#   ./link.sh             # apply
#
# Existing real files are moved aside to <name>.bak.<timestamp> rather than
# overwritten. Re-running is safe: correct links are left alone.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$REPO"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  echo "DRY RUN -- nothing will be changed"
  echo
fi

linked=0
already=0
backed_up=0

while IFS= read -r rel; do
  # Repo-only files that have no business in $HOME.
  case "$rel" in
    link.sh | .dotfiles.gitignore | README* | LICENSE*) continue ;;
    *.bak.*) continue ;;
  esac

  src="$REPO/$rel"
  dst="$HOME/$rel"

  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$src" ]; then
    already=$((already + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      echo "would back up and link: $rel"
    else
      echo "would link:             $rel"
    fi
    linked=$((linked + 1))
    continue
  fi

  mkdir -p "$(dirname "$dst")"

  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    backup="$dst.bak.$(date +%s)"
    mv "$dst" "$backup"
    echo "backed up: $rel -> $(basename "$backup")"
    backed_up=$((backed_up + 1))
  else
    rm -f "$dst"
  fi

  ln -s "$src" "$dst"
  echo "linked:    $rel"
  linked=$((linked + 1))
done < <(git ls-files)

echo
echo "linked/updated: $linked   already correct: $already   backed up: $backed_up"

if [ "$DRY_RUN" -eq 0 ] && [ "$linked" -gt 0 ]; then
  echo
  echo "Reload what you changed, e.g.:  hyprctl reload   |   omarchy restart shell"
fi
