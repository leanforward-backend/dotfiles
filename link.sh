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
#   ./link.sh --quiet     # apply; print only when something changed
#
# Existing real files are moved aside to <name>.bak.<timestamp> rather than
# overwritten. Re-running is safe: correct links are left alone.
#
# The script also points git at .githooks/, whose post-merge, post-checkout
# and post-commit hooks re-run it, so a pull or a commit that introduces new
# files links them without anyone remembering to.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$REPO"

DRY_RUN=0
QUIET=0
case "${1:-}" in
  --dry-run)
    DRY_RUN=1
    echo "DRY RUN -- nothing will be changed"
    echo
    ;;
  --quiet) QUIET=1 ;;
esac

# Newly staged files count as tracked, so a file added with `git add` links
# on the next run without waiting for a commit.
if [ "$DRY_RUN" -eq 0 ] && [ "$(git config --get core.hooksPath || true)" != ".githooks" ]; then
  git config core.hooksPath .githooks
  [ "$QUIET" -eq 1 ] || echo "installed git hooks: core.hooksPath = .githooks"
fi

linked=0
already=0
backed_up=0

while IFS= read -r rel; do
  # Repo-only files that have no business in $HOME.
  case "$rel" in
    link.sh | .dotfiles.gitignore | README* | LICENSE*) continue ;;
    .githooks/*) continue ;;
    *.bak.*) continue ;;
  esac

  src="$REPO/$rel"
  dst="$HOME/$rel"

  # Compare the link target itself, not the fully resolved path: repo files
  # may themselves be symlinks (the shared backgrounds are), and resolving
  # through them would make a correct link look wrong on every run.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
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

if [ "$QUIET" -eq 1 ] && [ "$linked" -eq 0 ]; then
  exit 0
fi

echo
echo "linked/updated: $linked   already correct: $already   backed up: $backed_up"

if [ "$DRY_RUN" -eq 0 ] && [ "$linked" -gt 0 ]; then
  echo
  echo "Reload what you changed, e.g.:  hyprctl reload   |   omarchy-restart-shell"
fi
