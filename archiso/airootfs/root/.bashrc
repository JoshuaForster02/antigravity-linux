# Flynn OS bash config
export TERM=linux
export EDITOR=vim
export PATH=/usr/local/bin:$PATH

# TRON prompt (fallback when not running flynn-ui)
PS1='\[\e[2;36m\][\[\e[1;37m\]root\[\e[0;36m\]@flynnos\[\e[2;36m\]]\[\e[1;36m\]▶ \[\e[0m\]'

# Auto-start Flynn UI in text sessions
if [[ $TERM == "linux" && $(tty) == /dev/tty2 ]]; then
    exec /usr/local/bin/flynn-ui
fi
