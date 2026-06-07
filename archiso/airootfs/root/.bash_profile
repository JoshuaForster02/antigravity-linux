# Flynn OS — auto-start X11 on tty1, else text shell
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec /usr/local/bin/flynn-startx
