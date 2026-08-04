#!/bin/bash
#
#===============================================================================
# Script                : webwall_installer.sh
# Purpose               : WebWall Kiosk Installer
#                         Prepares a Linux Mint 22.3 XFCE system for unattended kiosk operation.
#                         Installs all dependencies, configures the OS for always-on display, sets up
#                         autostart and cron schedules, and validates the installation.
# Prerequisites         : Complete before running this installer
#                         - Linux Mint 22.3 XFCE 64-bit installed
#                         - XFCE Desktop configured
#                         - Automatic login enabled during Linux installation
# Author                : Mike Perez
# GitHub                : https://github.com/mik3p3r3z
# Created               : 2026-07-31
# Version               : 1.0.0
#===============================================================================

set -euo pipefail

# Constants -----------------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly KIOSK_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
readonly KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6 || echo "/home/$KIOSK_USER")"
readonly WEBWALL_DIR="${KIOSK_HOME}/Desktop/webwall"
readonly LOG_FILE="${SCRIPT_DIR}/webwall_install.log"
readonly BRAVE_POLICY_DIR="/etc/brave/policies/managed"
readonly BRAVE_KEYRING="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
readonly BRAVE_SOURCES="/etc/apt/sources.list.d/brave-browser-release.sources"
readonly CRON_SCRIPT="webwall_cron.sh"
readonly AUTOSTART_SCRIPT="webwall_autostart.sh"
readonly TOTAL_STEPS=8

# Cron marker comments for idempotent replacement
readonly CRON_BEGIN="# >>> WebWall Kiosk Cron Jobs >>>"
readonly CRON_END="# <<< WebWall Kiosk Cron Jobs <<<"

# Track results for final summary
declare -a COMPLETED_TASKS=()
declare -a FAILED_TASKS=()
CURRENT_STEP=0

# Utility Functions ---------------------------------------------------------

# Timestamped log to stdout (also captured to LOG_FILE via tee)
log_info()    { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
log_success() { echo "[$(date '+%H:%M:%S')] [ OK ]  $*"; }
log_warn()    { echo "[$(date '+%H:%M:%S')] [WARN]  $*"; }
log_error()   { echo "[$(date '+%H:%M:%S')] [FAIL]  $*" >&2; }

# Print a progress banner for the current phase
step_header() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1"
    echo "══════════════════════════════════════════════════════════════"
}

# Record completed/failed tasks for the summary at the end
record_done()    { COMPLETED_TASKS+=("$1"); }
record_failure() { FAILED_TASKS+=("$1"); }

# Check whether a package is installed via dpkg
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }

# Check whether a command is on PATH
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Pre-flight Checks ---------------------------------------------------------

preflight_checks() {
    # Must be root
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This installer must be run as root or with sudo."
        exit 1
    fi

    # SUDO_USER must be set so we know which user owns the kiosk
    if [[ -z "${SUDO_USER:-}" ]]; then
        log_error "Could not determine the kiosk user. Run with: sudo ./$(basename "$0")"
        exit 1
    fi

    # Kiosk user must exist on the system
    if ! id "$KIOSK_USER" >/dev/null 2>&1; then
        log_error "Kiosk user '$KIOSK_USER' does not exist on this system."
        exit 1
    fi

    # Runtime scripts must be present in the source directory
    for f in "$CRON_SCRIPT" "$AUTOSTART_SCRIPT"; do
        if [[ ! -f "${SCRIPT_DIR}/${f}" ]]; then
            log_error "Required script '${f}' not found in ${SCRIPT_DIR}"
            exit 1
        fi
    done

    log_info "Kiosk user : $KIOSK_USER"
    log_info "Home dir   : $KIOSK_HOME"
    log_info "Install dir: $WEBWALL_DIR"
    log_info "Log file   : $LOG_FILE"
}

# Logging Setup -------------------------------------------------------------

setup_logging() {
    # Mirror all output to a log file alongside the installer
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         WebWall Kiosk Installer — $(date '+%Y-%m-%d %H:%M')         ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
}

# Step 1: Install System Packages -------------------------------------------

install_system_packages() {
    step_header "Install System Packages"

    export DEBIAN_FRONTEND=noninteractive

    # Packages required by the kiosk runtime scripts:
    #   feh               – image viewer for the slideshow display
    #   x11-xserver-utils – provides xset for disabling DPMS/blanking
    #   cron              – task scheduler for periodic captures and maintenance
    #   openssh-server    – remote administration access
    #   curl              – downloading the Brave repository key
    local packages=(
        "curl"
        "feh"
        "cron"
        "openssh-server"
        "x11-xserver-utils"
    )

    log_info "Updating APT package index…"
    apt-get update -qq

    log_info "Installing: ${packages[*]}"
    apt-get install -y -qq "${packages[@]}"

    # Verify each package
    local all_ok=true
    for pkg in "${packages[@]}"; do
        if pkg_installed "$pkg"; then
            log_success "$pkg"
        else
            log_error "$pkg failed to install"
            record_failure "Install $pkg"
            all_ok=false
        fi
    done

    # Enable NTP time synchronisation (carried over from original script)
    if cmd_exists timedatectl; then
        timedatectl set-ntp true
        log_success "NTP time synchronisation enabled"
    fi

    # Ensure cron service is enabled and running
    systemctl enable --now cron 2>/dev/null || true
    log_success "cron service enabled"

    if [[ "$all_ok" == true ]]; then
        record_done "System packages installed"
    fi
}

# Step 2: Install and Configure Brave Browser -------------------------------

install_brave_browser() {
    step_header "Install and Configure Brave Browser"

    # --- Configure APT repository and signing key (if not already present) ---
    if ! cmd_exists brave-browser; then
        log_info "Configuring Brave Browser APT repository…"
        mkdir -p /usr/share/keyrings

        curl -fsSLo "$BRAVE_KEYRING" \
            "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
        chmod 644 "$BRAVE_KEYRING"

        curl -fsSLo "$BRAVE_SOURCES" \
            "https://brave-browser-apt-release.s3.brave.com/brave-browser.sources"
        chmod 644 "$BRAVE_SOURCES"

        log_success "Brave repository and signing key configured"

        apt-get update -qq
    else
        log_info "Brave Browser already installed; will check for updates…"
    fi

    # --- Install or update Brave ---
    apt-get install -y -qq brave-browser

    if cmd_exists brave-browser; then
        log_success "Brave Browser installed ($(brave-browser --version 2>/dev/null || echo 'version unknown'))"
        record_done "Brave Browser installed"
    else
        log_error "Brave Browser installation failed"
        record_failure "Install Brave Browser"
        return
    fi

    # --- Managed policies for unattended headless screenshot capture ---
    # These disable all interactive prompts, dialogs, and background services
    # that are irrelevant when Brave is used solely for --headless --screenshot.
    log_info "Writing managed policies for headless kiosk mode…"
    mkdir -p "$BRAVE_POLICY_DIR"

    cat > "${BRAVE_POLICY_DIR}/webwall_kiosk.json" << 'POLICIES'
{
    "BrowserSignin": 0,
    "SyncDisabled": true,
    "PasswordManagerEnabled": false,
    "AutoFillAddressEnabled": false,
    "AutoFillCreditCardEnabled": false,
    "BackgroundModeEnabled": false,
    "DefaultBrowserSettingEnabled": false,
    "BrowserLabsEnabled": false,
    "ExtensionInstallBlocklist": ["*"],
    "ExtensionInstallAllowlist": [],
    "DefaultNotificationsSetting": 2,
    "NotificationsAllowedForUrls": [],
    "NotificationsBlockedForUrls": ["*"],
    "DownloadRestrictions": 2,
    "PromptForDownloadLocation": false,
    "SafeBrowsingEnabled": false,
    "TranslateEnabled": false,
    "IncognitoModeAvailability": 0
}
POLICIES
    chmod 644 "${BRAVE_POLICY_DIR}/webwall_kiosk.json"
    log_success "Managed policies installed (headless screenshot mode)"

    # --- Create a headless user-data directory with first-run sentinel ---
    # The "First Run" file suppresses the welcome / first-run tab that Brave
    # would otherwise attempt to show on initial launch.
    local brave_data="${KIOSK_HOME}/.config/brave-headless"
    mkdir -p "$brave_data"
    touch "${brave_data}/First Run"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$brave_data"
    log_success "Headless user-data directory prepared"

    record_done "Brave Browser configured for unattended operation"
}

# Step 3: Install Kiosk Files -----------------------------------------------

install_kiosk_files() {
    step_header "Install Kiosk Files"

    # Create the destination directory
    mkdir -p "$WEBWALL_DIR"

    # Copy runtime scripts from the source directory
    local scripts=("$CRON_SCRIPT" "$AUTOSTART_SCRIPT")

    for script in "${scripts[@]}"; do
        local src="${SCRIPT_DIR}/${script}"
        local dst="${WEBWALL_DIR}/${script}"

        cp "$src" "$dst"
        log_info "Copied ${script} → ${WEBWALL_DIR}/"

        # Fix CRLF line endings (prevents "\r: command not found" errors)
        sed -i 's/\r$//' "$dst"

        # Replace INSTALL_DIR placeholder with actual path (no-op if absent)
        sed -i "s|INSTALL_DIR|${WEBWALL_DIR}|g" "$dst"

        # Fix hardcoded /home/kiosk path to match actual kiosk user
        sed -i "s|/home/kiosk/Desktop/webwall|${WEBWALL_DIR}|g" "$dst"

        # Make scripts executable
        chmod 755 "$dst"
    done

    log_info "Fixed CRLF endings, configured paths, set executable permissions"

    # Create the cron log file so the cron redirect target exists
    touch "${WEBWALL_DIR}/webwall_cron.log"

    # Set ownership for the entire WebWall directory tree
    chown -R "$KIOSK_USER:$KIOSK_USER" "$WEBWALL_DIR"

    log_success "Kiosk files installed to ${WEBWALL_DIR}"
    record_done "Kiosk files installed with correct ownership and permissions"
}

# Step 4: Configure Power Management and Screensaver ------------------------

configure_power_management() {
    step_header "Disable Screensaver, DPMS, Suspend, and Hibernate"

    # --- Mask systemd sleep/suspend/hibernate targets ---
    # Prevents the OS from entering any low-power state regardless of other
    # desktop environment settings.
    log_info "Masking systemd power-state targets…"
    systemctl mask sleep.target 2>/dev/null || true
    systemctl mask suspend.target 2>/dev/null || true
    systemctl mask hibernate.target 2>/dev/null || true
    systemctl mask hybrid-sleep.target 2>/dev/null || true
    log_success "Systemd suspend, hibernate, and sleep targets masked"

    # --- Remove XFCE Power Manager and screensaver autostart entries ---
    local pm_desktop="/etc/xdg/autostart/xfce4-power-manager.desktop"
    if [[ -f "$pm_desktop" ]]; then
        rm -f "$pm_desktop"
        log_success "XFCE Power Manager autostart entry removed"
    else
        log_info "XFCE Power Manager autostart already absent"
    fi

    local ss_desktop="/etc/xdg/autostart/xfce4-screensaver.desktop"
    if [[ -f "$ss_desktop" ]]; then
        rm -f "$ss_desktop"
        log_success "XFCE screensaver autostart entry removed"
    fi

    # --- Write XFCE xfconf settings (power manager + screensaver channels) ---
    # These XML files are read at session start and pre-configure the channels
    # so the user is never prompted and no power-saving action is taken.
    local xfconf_dir="${KIOSK_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$xfconf_dir"

    cat > "${xfconf_dir}/xfce4-power-manager.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="power-button-action" type="uint" value="0"/>
    <property name="sleep-button-action" type="uint" value="0"/>
    <property name="hibernate-button-action" type="uint" value="0"/>
    <property name="inactivity-onac" type="uint" value="0"/>
    <property name="inactivity-sleep-mode" type="uint" value="0"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
    <property name="logind-handle-power-key" type="bool" value="false"/>
    <property name="logind-handle-suspend-key" type="bool" value="false"/>
    <property name="logind-handle-hibernate-key" type="bool" value="false"/>
  </property>
</channel>
XML

    cat > "${xfconf_dir}/xfce4-screensaver.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
    <property name="mode" type="int" value="0"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
XML

    chown -R "$KIOSK_USER:$KIOSK_USER" "$xfconf_dir"
    log_success "XFCE power-manager and screensaver settings written"

    # --- Create .xprofile to disable X-level display blanking at login ---
    # Runs when the user's X session starts; disables screen saver, DPMS,
    # and all blanking at the display-server level.
    local xprofile="${KIOSK_HOME}/.xprofile"
    cat > "$xprofile" << 'XPROFILE'
#!/bin/bash
# WebWall Kiosk — X session display configuration
# Disables screen saver, screen blanking, and DPMS at login.

xset s off          # Disable screen saver activation
xset s noblank      # Do not blank the screen
xset s 0 0          # Set screen-saver timeout to zero
xset -dpms          # Disable DPMS entirely
xset dpms 0 0 0     # Set all DPMS timeouts to zero (redundant safety)
XPROFILE
    chmod 755 "$xprofile"
    chown "$KIOSK_USER:$KIOSK_USER" "$xprofile"
    log_success ".xprofile created (X-level DPMS and blanking disabled)"

    # --- Disable xscreensaver if the package is present ---
    if pkg_installed xscreensaver; then
        local xss_rc="${KIOSK_HOME}/.xscreensaver"
        cat > "$xss_rc" << 'XSS'
timeout:	0
cycle:		0
lock:		False
XSS
        chown "$KIOSK_USER:$KIOSK_USER" "$xss_rc"
        log_success "xscreensaver disabled via ~/.xscreensaver"
    fi

    record_done "Power management, screensaver, DPMS, and suspend disabled"
}

# Step 5: Configure Kiosk Autostart -----------------------------------------

configure_autostart() {
    step_header "Configure Kiosk Autostart"

    local autostart_dir="${KIOSK_HOME}/.config/autostart"
    mkdir -p "$autostart_dir"

    local desktop_file="${autostart_dir}/webwall.desktop"

    # Remove existing entry so re-runs produce a clean file
    rm -f "$desktop_file"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Type=Application
Name=WebWall
Comment=WebWall Kiosk Display
Exec=${WEBWALL_DIR}/${AUTOSTART_SCRIPT}
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Terminal=false
EOF

    chmod 644 "$desktop_file"
    chown "$KIOSK_USER:$KIOSK_USER" "$desktop_file"

    log_success "Autostart entry created: ${desktop_file}"
    record_done "Kiosk autostart configured"
}

# Step 6: Configure Scheduled Tasks (Cron) ----------------------------------

configure_cron() {
    step_header "Configure Scheduled Tasks"

    local cron_script="${WEBWALL_DIR}/${CRON_SCRIPT}"
    local cron_log="${WEBWALL_DIR}/webwall_cron.log"

    # --- Read existing crontab and remove previous WebWall block ---
    # Uses marker comments so re-runs never create duplicate entries.
    local existing
    existing=$(crontab -u "$KIOSK_USER" -l 2>/dev/null \
        | sed "/${CRON_BEGIN}/,/${CRON_END}/d" \
        || true)

    # --- Build the new WebWall cron block ---
    local block=""
    block+="${CRON_BEGIN}"$'\n'
    # Screenshot capture — every 5 minutes
    block+="*/5 * * * * ${cron_script} >> ${cron_log} 2>&1"$'\n'
    # Weekly reboot warning + reboot — Saturday 1:50 AM (reboots at 1:55)
    block+="50 1 * * 6 /sbin/shutdown -r +5 \"WebWall kiosk: scheduled maintenance reboot in 5 minutes\""$'\n'
    # Weekly log cleanup — Sunday 4:00 AM (remove logs older than 7 days)
    block+="0 4 * * 0 find ${WEBWALL_DIR} -name \"*.log\" -type f -mtime +7 -delete"$'\n'
    block+="${CRON_END}"$'\n'

    # Combine existing entries with the new WebWall block
    printf '%s\n%s' "$existing" "$block" | crontab -u "$KIOSK_USER" -

    log_success "Cron jobs installed for user ${KIOSK_USER}:"
    log_info "  • Screenshot capture  — every 5 minutes"
    log_info "  • Weekly reboot       — Saturday 1:50 AM (5-min warning, reboots at 1:55)"
    log_info "  • Weekly log cleanup  — Sunday 4:00 AM (remove logs > 7 days)"

    record_done "Scheduled tasks configured (capture, reboot, log cleanup)"
}

# Step 7: Configure SSH Server ----------------------------------------------

configure_ssh() {
    step_header "Configure SSH Server"

    systemctl enable ssh 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl start ssh 2>/dev/null || true

    if systemctl is-active --quiet ssh; then
        log_success "SSH server is active and enabled on boot"
        record_done "SSH server configured and running"
    else
        log_error "SSH server failed to start"
        record_failure "Configure SSH server"
    fi
}

# Step 8: Validate Installation ---------------------------------------------

validate_installation() {
    step_header "Validate Installation"

    local failed=0

    # Helper: check a condition and log the result
    _check() {
        local desc="$1"
        local result="$2"
        if [[ "$result" == "pass" ]]; then
            log_success "$desc"
        else
            log_error "$desc"
            ((failed++))
        fi
    }

    # --- Packages ---
    pkg_installed feh                && _check "feh installed"                pass || _check "feh installed"                fail
    pkg_installed cron               && _check "cron installed"               pass || _check "cron installed"               fail
    pkg_installed openssh-server     && _check "openssh-server installed"     pass || _check "openssh-server installed"     fail
    pkg_installed x11-xserver-utils  && _check "x11-xserver-utils installed"  pass || _check "x11-xserver-utils installed"  fail

    # --- Brave Browser ---
    cmd_exists brave-browser         && _check "Brave Browser installed"      pass || _check "Brave Browser installed"      fail
    [[ -x /usr/bin/brave-browser ]]   && _check "Brave binary is executable"   pass || _check "Brave binary is executable"   fail
    [[ -f "${BRAVE_POLICY_DIR}/webwall_kiosk.json" ]] && _check "Brave managed policy file exists" pass || _check "Brave managed policy file exists" fail

    # --- SSH ---
    systemctl is-enabled --quiet ssh && _check "SSH enabled on boot"          pass || _check "SSH enabled on boot"          fail
    systemctl is-active  --quiet ssh && _check "SSH service running"          pass || _check "SSH service running"          fail

    # --- Cron ---
    crontab -u "$KIOSK_USER" -l 2>/dev/null | grep -q "$CRON_SCRIPT" \
        && _check "Cron: screenshot capture job exists" pass \
        || _check "Cron: screenshot capture job exists" fail
    crontab -u "$KIOSK_USER" -l 2>/dev/null | grep -q 'shutdown.*-r' \
        && _check "Cron: weekly reboot job exists" pass \
        || _check "Cron: weekly reboot job exists" fail
    crontab -u "$KIOSK_USER" -l 2>/dev/null | grep -q 'mtime.*delete' \
        && _check "Cron: weekly log cleanup job exists" pass \
        || _check "Cron: weekly log cleanup job exists" fail

    # --- WebWall files ---
    [[ -d "$WEBWALL_DIR" ]]                                && _check "WebWall directory exists"       pass || _check "WebWall directory exists"       fail
    [[ -x "${WEBWALL_DIR}/${CRON_SCRIPT}" ]]               && _check "webwall_cron.sh installed+exec"  pass || _check "webwall_cron.sh installed+exec"  fail
    [[ -x "${WEBWALL_DIR}/${AUTOSTART_SCRIPT}" ]]          && _check "webwall_autostart.sh installed" pass || _check "webwall_autostart.sh installed" fail
    [[ "$(stat -c%U "$WEBWALL_DIR")" == "$KIOSK_USER" ]]   && _check "WebWall dir owned by $KIOSK_USER" pass || _check "WebWall dir owned by $KIOSK_USER" fail

    # --- Autostart ---
    [[ -f "${KIOSK_HOME}/.config/autostart/webwall.desktop" ]] \
        && _check "Autostart desktop entry exists" pass \
        || _check "Autostart desktop entry exists" fail
    [[ "$(stat -c%U "${KIOSK_HOME}/.config/autostart/webwall.desktop")" == "$KIOSK_USER" ]] \
        && _check "Autostart entry owned by $KIOSK_USER" pass \
        || _check "Autostart entry owned by $KIOSK_USER" fail

    # --- Power management ---
    systemctl is-masked --quiet sleep.target     && _check "sleep.target masked"       pass || _check "sleep.target masked"       fail
    systemctl is-masked --quiet suspend.target   && _check "suspend.target masked"     pass || _check "suspend.target masked"     fail
    systemctl is-masked --quiet hibernate.target  && _check "hibernate.target masked"   pass || _check "hibernate.target masked"   fail
    [[ ! -f /etc/xdg/autostart/xfce4-power-manager.desktop ]] \
        && _check "XFCE Power Manager autostart removed" pass \
        || _check "XFCE Power Manager autostart removed" fail
    [[ -f "${KIOSK_HOME}/.xprofile" ]] && _check ".xprofile exists" pass || _check ".xprofile exists" fail

    # --- Overall result ---
    echo ""
    if [[ $failed -eq 0 ]]; then
        log_success "All ${TOTAL_STEPS} validation checks passed"
    else
        log_warn "$failed validation check(s) failed — review log: $LOG_FILE"
    fi
}

# Summary--------------------------------------------------------------------

display_summary() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    Installation Summary                       ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Completed tasks:                                             ║"

    for task in "${COMPLETED_TASKS[@]}"; do
        printf "║    ✓ %-56s ║\n" "$task"
    done

    if [[ ${#FAILED_TASKS[@]} -gt 0 ]]; then
        echo "║  ─────────────────────────────────────────────────────────── ║"
        echo "║  Failed tasks:                                                ║"
        for task in "${FAILED_TASKS[@]}"; do
            printf "║    ✗ %-56s ║\n" "$task"
        done
    fi

    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Kiosk user      : $(printf '%-40s' "$KIOSK_USER") ║"
    echo "║  Install dir     : $(printf '%-40s' "$WEBWALL_DIR") ║"
    echo "║  Autostart entry : $(printf '%-40s' "~/.config/autostart/webwall.desktop") ║"
    echo "║  Log file        : $(printf '%-40s' "$LOG_FILE") ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  *** REBOOT REQUIRED — reboot to start kiosk operation ***   ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
}

# Main Entry Point ----------------------------------------------------------

main() {
    preflight_checks
    setup_logging

    install_system_packages
    install_brave_browser
    install_kiosk_files
    configure_power_management
    configure_autostart
    configure_cron
    configure_ssh
    validate_installation

    display_summary
}

main "$@"
