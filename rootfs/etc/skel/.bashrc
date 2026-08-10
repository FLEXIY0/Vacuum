# Vacuum — interactive shell setup.

case $- in
    *i*) ;;
    *) return ;;
esac

# Prompt: dim path, accent-cyan marker, nothing else.
if [ "$(id -u)" -eq 0 ]; then
    PS1='\[\e[38;5;167m\]\w\[\e[0m\] \[\e[38;5;167m\]#\[\e[0m\] '
else
    PS1='\[\e[38;5;245m\]\w\[\e[0m\] \[\e[38;5;80m\]\$\[\e[0m\] '
fi

alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -lha'
alias grep='grep --color=auto'
alias df='df -h'
alias free='free -m'

export EDITOR="${EDITOR:-vi}"
export PAGER="${PAGER:-less}"
export LESS='-R'

HISTSIZE=5000
HISTFILESIZE=5000
HISTCONTROL=ignoreboth
shopt -s histappend checkwinsize

# Greeting, once per login rather than once per shell.
if [ -z "$VACUUM_GREETED" ] && [ -r /usr/share/vacuum/logo.txt ]; then
    export VACUUM_GREETED=1
    printf '\e[38;5;80m'
    cat /usr/share/vacuum/logo.txt
    printf '\e[0m'
    if [ -r /etc/vacuum-release ]; then
        ( . /etc/vacuum-release
          printf '\e[2m        %s %s · Super+Return terminal · Super+d run\e[0m\n\n' \
              "$NAME" "$VERSION" )
    fi
fi
