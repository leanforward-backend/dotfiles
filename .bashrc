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

# foot passes Ctrl+V through raw (so Claude Code can paste images); make it
# paste clipboard text at the cursor here instead of readline's quoted-insert.
_paste_clipboard() {
  local clip
  clip=$(wl-paste --no-newline --type text 2>/dev/null) || return
  READLINE_LINE="${READLINE_LINE:0:READLINE_POINT}${clip}${READLINE_LINE:READLINE_POINT}"
  READLINE_POINT=$((READLINE_POINT + ${#clip}))
}
bind -x '"\C-v": _paste_clipboard'


# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
[[ -r "$HOME/.grok/completions/bash/grok.bash" ]] && source "$HOME/.grok/completions/bash/grok.bash"
# <<< grok installer <<<

# >>> Codex installer >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< Codex installer <<<
