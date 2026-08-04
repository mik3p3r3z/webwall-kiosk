#!/bin/bash
#
#===============================================================================
# Script  : webwall_cron.sh
# Purpose : Capture screenshots of websites
# Author  : Mike Perez
# GitHub  : https://github.com/mik3p3r3z/
# Created : 2026-07-31
# Version : 1.0.0
#===============================================================================

set -Eeuo pipefail

# Constants -------------------------------------------------------------------

IMAGE_DIR="/home/kiosk/Desktop/webwall"
BROWSER="/usr/bin/brave-browser"
FLAGS=(
  --headless
  --force-device-scale-factor=1.0
  --no-sandbox
  --disable-dev-shm-usage
  --hide-scrollbars
  --disable-dbus
  --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

# Functions -------------------------------------------------------------------

# Capture and swap images
capture_site() {
  local url="$1"
  local out_file="$2"
  local win_size="$3"
  # Strip .png and add .tmp.png so the browser recognizes the extension
  local temp_file="${out_file%.png}.tmp.png"

  # Capture to a temporary file (2>/dev/null hides harmless D-Bus/GPU errors)
  timeout 45 "$BROWSER" "${FLAGS[@]}" --window-size="$win_size" --screenshot="$temp_file" "$url" 2>/dev/null

  # Only replace the old image if the new one is valid (>10KB prevents blank/error pages)
  if [ -s "$temp_file" ] && [ "$(stat -c%s "$temp_file")" -gt 10000 ]; then
    mv "$temp_file" "$out_file"
  else
    # If it failed, discard the temp file and keep the old image on screen
    rm -f "$temp_file"
  fi

  # Wait 10-15 seconds between sites to avoid rate limits
  sleep $(( ( RANDOM % 6 ) + 10 ))
}

# Main ------------------------------------------------------------------------

main() {
    capture_site "https://2news.com"   "$IMAGE_DIR/ktvn.png" "1350,2400"
    capture_site "https://mynews4.com"  "$IMAGE_DIR/krnv.png" "1080,1920"
    capture_site "https://kolotv.com"   "$IMAGE_DIR/kolo.png" "1440,2560"
    capture_site "https://rgj.com"      "$IMAGE_DIR/rgj.png"  "1200,2133"
}

main "$@"
