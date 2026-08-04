#!/bin/bash
#
#===============================================================================
# Script  : webwall_autostart.sh
# Purpose : Configure displays and launch dashboard images
# Author  : Mike Perez
# GitHub  : https://github.com/mik3p3r3z
# Created : 2026-07-31
# Version : 1.0.0
#===============================================================================

set -Eeuo pipefail

# Constants -------------------------------------------------------------------

readonly VERSION="1.0.0"
readonly DISPLAY=":0"
readonly IMAGE_DIR="/home/kiosk/Desktop/webwall"

# Main ------------------------------------------------------------------------

main() {
    export DISPLAY=:0

    # Disable screen blanking and power managmement
    xset -dpms; xset s off; xset s noblank

    # Configure monitor layout
    xrandr --output DP-4 --rotate left --pos 0x0 \
           --output DP-2 --rotate left --pos 1080x0 \
           --output DP-3 --rotate left --pos 2160x0 \
           --output DP-1 --rotate left --pos 3240x0

    sleep 2

    # Close all existing image viewers
    killall feh 2>/dev/null || true

    IMAGE_DIR="/home/kiosk/Desktop/webwall"

        # Launch images
    feh --borderless --hide-pointer --no-fehbg --scale-down --reload 10 --geometry 1080x1920+0+0 "$IMAGE_DIR/ktvn.png" &

    feh --borderless --hide-pointer --no-fehbg --scale-down --reload 10 --geometry 1080x1920+1080+0 "$IMAGE_DIR/krnv.png" &

    feh --borderless --hide-pointer --no-fehbg --scale-down --reload 10 --geometry 1080x1920+2160+0 "$IMAGE_DIR/kolo.png" &

    feh --borderless --hide-pointer --no-fehbg --scale-down --reload 10 --geometry 1080x1920+3420+0 "$IMAGE_DIR/rgj.png" &
}

main "$@"
