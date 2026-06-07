#!/bin/sh
# Flynn OS Linux — Terminal UI
# TRON-inspired shell running on top of Linux kernel + BusyBox

# ANSI color codes
CY='\033[0;36m'   # cyan
LCY='\033[1;36m'  # light cyan
WHT='\033[1;37m'  # white
DIM='\033[2;36m'  # dim cyan
GRN='\033[0;32m'  # green
RED='\033[0;31m'  # red
RST='\033[0m'     # reset
BOLD='\033[1m'

# Screen setup
tput clear
tput civis  # hide cursor

# ── Draw border ──────────────────────────────────────────────────────────────
COLS=$(tput cols)
ROWS=$(tput lines)

draw_hline() {
    printf "${CY}"
    printf '%*s' "$COLS" '' | tr ' ' '='
    printf "${RST}\n"
}

# ── Boot splash ──────────────────────────────────────────────────────────────
tput cup 0 0
draw_hline
tput cup 1 0
printf "${LCY}%*s${RST}\n" $(( (COLS + 20) / 2 )) "F L Y N N   O S   //   L I N U X"
tput cup 2 0
draw_hline

# Boot status messages
sleep 0.1; printf "${DIM}  >> KERNEL               ${GRN}[ Linux $(uname -r) ]${RST}\n"
sleep 0.1; printf "${DIM}  >> INIT SYSTEM          ${GRN}[ OK ]${RST}\n"
sleep 0.1; printf "${DIM}  >> FILESYSTEMS          ${GRN}[ OK ]${RST}\n"
sleep 0.1; printf "${DIM}  >> NETWORK              ${GRN}[ READY ]${RST}\n"
sleep 0.1; printf "\n${WHT}  System online. Type 'help' for commands.${RST}\n\n"

tput cnorm  # show cursor

# ── Shell loop ───────────────────────────────────────────────────────────────
while true; do
    printf "${LCY}[flynn@linux]>${RST} "
    read -r CMD

    case "$CMD" in
        help)
            printf "${LCY}  Commands:${RST}\n"
            printf "    help      -- this message\n"
            printf "    sysinfo   -- system info\n"
            printf "    ls        -- list files\n"
            printf "    ps        -- processes\n"
            printf "    mem       -- memory usage\n"
            printf "    reboot    -- reboot\n"
            printf "    halt      -- power off\n"
            printf "    sh        -- drop to ash shell\n"
            ;;
        sysinfo)
            printf "${LCY}  SYSTEM${RST}\n"
            printf "  OS       Flynn OS Linux\n"
            printf "  Kernel   $(uname -r)\n"
            printf "  Arch     $(uname -m)\n"
            printf "  Uptime   $(cat /proc/uptime | awk '{printf "%.0fs", $1}')\n"
            ;;
        ls)     ls --color=auto ;;
        ps)     ps aux 2>/dev/null || ps ;;
        mem)    free -h 2>/dev/null || cat /proc/meminfo | head -5 ;;
        reboot) reboot ;;
        halt|poweroff) poweroff ;;
        sh|bash) exec /bin/sh ;;
        "")     ;;
        *)
            # Try to run as a system command
            eval "$CMD" 2>/dev/null || \
                printf "${RED}  Unknown: $CMD  (type 'help')${RST}\n"
            ;;
    esac
    printf "\n"
done
