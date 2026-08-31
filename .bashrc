# Omarchy environment (OMARCHY_PATH + PATH), needed even for non-interactive shells
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

# If not running interactively, don't do anything else (leave this above the rc source)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

# Dotfiles: bare git repo tracking select files in $HOME directly (no symlinks)
dotfiles() {
  git --git-dir="$HOME/.dotfiles.git" --work-tree="$HOME" "$@"
}


# Added by Antigravity CLI installer
export PATH="/home/toby/.local/bin:$PATH"
