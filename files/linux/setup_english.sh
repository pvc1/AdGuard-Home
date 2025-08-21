#!/bin/bash

# AdGuard Home Easy Setup by Internet Helper v1.0 (Start)

# Exit the script on any error, including errors in pipelines (pipes)
set -e
set -o pipefail

# --- VARIABLES AND CONSTANTS ---
# Colors for output
C_RESET='\033[0m';
C_RED='\033[0;31m';
C_GREEN='\033[38;2;0;210;106m';
C_YELLOW='\033[0;33m';
C_BLUE='\033[0;34m';
C_CYAN='\033[0;36m'

# File paths and URLs
ADH_DIR="/opt/AdGuardHome";
ADH_CONFIG_FILE="${ADH_DIR}/AdGuardHome.yaml";
ADH_CONFIG_BACKUP="${ADH_DIR}/AdGuardHome.yaml.initial_bak"
ADH_BACKUP_DIR="${ADH_DIR}/backup"
LOCAL_CONFIG_RU="${ADH_BACKUP_DIR}/AdGuardHome.ru.yaml"
LOCAL_CONFIG_EN="${ADH_BACKUP_DIR}/AdGuardHome.en.yaml"
LOCAL_CONFIG_STD="${ADH_BACKUP_DIR}/AdGuardHome.standard.yaml"
LOCAL_CONFIG_USER="${ADH_BACKUP_DIR}/AdGuardHome.user_backup.yaml"
SET_DNS_SCRIPT_PATH="/opt/set-dns.sh";
SERVICE_FILE_PATH="/etc/systemd/system/set-dns.service"
RESOLV_CONF_PATH="/etc/resolv.conf";
RESOLV_BACKUP_PATH="/etc/resolv.conf.adh-backup"
ADH_SERVICE_NAME="AdGuardHome.service"
ADH_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"
CONFIG_URL_RU="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/refs/heads/main/files/russian/AdGuardHome.yaml"
CONFIG_URL_EN="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/refs/heads/main/files/english/AdGuardHome.yaml"

# --- TRAP AND CLEANUP FUNCTIONS ---
# Catches script exit and performs a rollback on error.
handle_exit() {
    local EXIT_CODE=$?
    chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 130 ] && [ $EXIT_CODE -ne 100 ]; then
        printf "\n${C_RED}ERROR: Script exited with code %s.${C_RESET}\n" "$EXIT_CODE"
        printf "${C_YELLOW}Rolling back changes...${C_RESET}\n"; restore_resolv_conf; printf "${C_GREEN}Rollback complete.${C_RESET}\n"
    fi
}

# Catches script interruption (Ctrl+C) and performs a rollback.
handle_interrupt() {
    printf "\n\n${C_YELLOW}Script interrupted. Rolling back changes...${C_RESET}\n"
    restore_resolv_conf
    printf "${C_GREEN}Rollback complete.${C_RESET}\n"
    exit 130
}

trap 'handle_exit' EXIT
trap 'handle_interrupt' SIGINT SIGTERM SIGHUP

# --- HELPER FUNCTIONS ---
# Prints an informational message in blue.
info() { printf "${C_BLUE}> %s${C_RESET}\n" "$1"; }
# Prints a success message in green.
success() { printf "${C_GREEN}✓ %s${C_RESET}\n" "$1"; }
# Prints a warning message in yellow.
warning() { printf "${C_YELLOW}! %s${C_RESET}\n" "$1"; }
# Prints an error message in red.
error() { printf "${C_RED}✗ %s${C_RESET}\n" "$1"; }

# Prompts the user for a "yes" or "no" answer.
prompt_yes_no() {
    local prompt_text="$1"
    while true; do read -p "$prompt_text (1 - yes, 2 - no): " choice; case $choice in 1) return 0 ;; 2) return 1 ;; *) warning "Invalid input." ;; esac; done
}

# Downloads a configuration file, using a local copy on failure.
get_config() {
    local remote_url="$1"; local local_path="$2"
    if curl -s -S -L -o "$ADH_CONFIG_FILE" "$remote_url"; then
        cp "$ADH_CONFIG_FILE" "$local_path"
    else
        warning "Failed to download the latest configuration. Using a local copy."
        if [ -f "$local_path" ]; then cp "$local_path" "$ADH_CONFIG_FILE"; else error "Local copy not found!"; return 1; fi
    fi
}

# Waits for the AdGuard Home service to start for up to 15 seconds.
wait_for_adh_service() {
    for i in {1..15}; do if systemctl is-active --quiet "$ADH_SERVICE_NAME"; then sleep 0.5; return 0; fi; sleep 1; done
    error "The AdGuard Home service did not start within 15 seconds."; return 1
}

# Checks if AdGuard Home is installed.
is_adh_installed() { [ -f "$ADH_CONFIG_FILE" ] && systemctl cat "$ADH_SERVICE_NAME" &>/dev/null; }
# Checks if the `set-dns.service` integration service is installed.
is_service_installed() { [ -f "$SERVICE_FILE_PATH" ]; }
# Checks if the AdGuard Home service is currently active.
is_adh_active() { is_adh_installed && systemctl is-active --quiet "$ADH_SERVICE_NAME"; }

# Creates a backup of the /etc/resolv.conf file.
backup_resolv_conf() { if [ ! -f "$RESOLV_BACKUP_PATH" ]; then cp -p "$RESOLV_CONF_PATH" "$RESOLV_BACKUP_PATH"; fi; }
# Restores the /etc/resolv.conf file from a backup.
restore_resolv_conf() { if [ -f "$RESOLV_BACKUP_PATH" ]; then chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; cp -p "$RESOLV_BACKUP_PATH" "$RESOLV_CONF_PATH"; rm -f "$RESOLV_BACKUP_PATH"; fi; }

# Performs initial system checks (permissions, dependencies, OS).
initial_checks() {
    if [ "$EUID" -ne 0 ]; then error "This script must be run with superuser privileges (e.g., via sudo)."; exit 1; fi
    local dependencies=("curl" "systemctl" "chattr" "logname" "tee" "grep" "awk" "sed" "hostname" "yq" "lsof"); for cmd in "${dependencies[@]}"; do if ! command -v "$cmd" &>/dev/null; then if [ "$cmd" = "yq" ]; then warning "yq not found. Installing..."; install_yq; else error "Required utility '$cmd' not found."; exit 1; fi; fi; done
    if [ -f /etc/os-release ]; then . /etc/os-release; case "$ID" in debian|ubuntu) PKG_UPDATER="apt-get update -y"; PKG_INSTALLER="apt-get install -y"; DNS_PACKAGE="dnsutils" ;; centos|almalinux|rocky|fedora) PKG_UPDATER=""; if [ "$ID" = "fedora" ]; then PKG_INSTALLER="dnf install -y"; else PKG_INSTALLER="yum install -y"; fi; DNS_PACKAGE="bind-utils" ;; *) error "Unsupported operating system: $ID"; exit 1 ;; esac; else error "Could not determine the operating system."; exit 1; fi
    if ! command -v dig &>/dev/null; then
        warning "'dig' is required for advanced DNS checks. Installing..."
        if [ -n "$PKG_UPDATER" ]; then $PKG_UPDATER &>/dev/null; fi
        $PKG_INSTALLER $DNS_PACKAGE &>/dev/null
        success "'dig' has been installed successfully!"
    fi
}

# Installs the yq utility if it is missing.
install_yq() {
    if [ ! -f "/usr/local/bin/yq" ]; then
        case "$(uname -m)" in
            x86_64) ARCH="amd64" ;;
            aarch64) ARCH="arm64" ;;
            armv7l) ARCH="arm" ;;
            *) error "Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac
        wget "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -O /usr/local/bin/yq && \
        chmod +x /usr/local/bin/yq && \
        success "yq has been installed successfully!"
    fi
}

# Creates a script and a systemd service to automatically set DNS to 127.0.0.1.
create_integration_services() {
    cat > "$SET_DNS_SCRIPT_PATH" << 'EOF'
#!/bin/bash
set -e
RESOLV_CONF="/etc/resolv.conf"; RESOLV_BACKUP="/etc/resolv.conf.adh-backup"
if [ ! -f "$RESOLV_BACKUP" ] && [ -f "$RESOLV_CONF" ]; then cp "$RESOLV_CONF" "$RESOLV_BACKUP"; fi
if ! systemctl is-active --quiet AdGuardHome; then
    systemctl enable --now AdGuardHome >/dev/null 2>&1
    if ! systemctl is-active --quiet AdGuardHome; then if [ -f "$RESOLV_BACKUP" ]; then chattr -i "$RESOLV_CONF" 2>/dev/null || true; cp "$RESOLV_BACKUP" "$RESOLV_CONF"; chmod 644 "$RESOLV_CONF"; chattr +i "$RESOLV_CONF"; exit 1; fi; fi
fi
TEMP_FILE=$(mktemp); { echo "options edns0"; echo "options trust-ad"; echo "nameserver 127.0.0.1"; echo "nameserver 1.1.1.1"; echo "nameserver 1.0.0.1"; echo "nameserver 8.8.8.8"; echo "nameserver 8.8.4.4"; } > "$TEMP_FILE"
chattr -i "$RESOLV_CONF" 2>/dev/null || true; cp "$TEMP_FILE" "$RESOLV_CONF"; chmod 644 "$RESOLV_CONF"; chattr +i "$RESOLV_CONF"; rm "$TEMP_FILE"
EOF
    chmod +x "$SET_DNS_SCRIPT_PATH"; cat > "$SERVICE_FILE_PATH" << EOF
[Unit]
Description=Set DNS to AdGuard Home (127.0.0.1)
After=network-online.target ${ADH_SERVICE_NAME}
Wants=network-online.target
Requires=${ADH_SERVICE_NAME}
[Service]
Type=oneshot
ExecStart=/opt/set-dns.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; if ! systemctl enable --now set-dns.service >/dev/null 2>&1; then return 1; fi
}

# Checks if port 53 is occupied by systemd-resolved and offers to fix the conflict.
check_and_fix_port_53() {
    if lsof -i :53 | grep -q 'systemd-r'; then
        warning "Conflict detected: Port 53 is occupied by the systemd-resolved service."
        if prompt_yes_no "Do you want the script to automatically free this port?"; then
            info "Applying fix for systemd-resolved..."
            
            mkdir -p /etc/systemd/resolved.conf.d
            cat > /etc/systemd/resolved.conf.d/adguardhome.conf <<EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
            
            if [ -f /etc/resolv.conf ]; then mv /etc/resolv.conf /etc/resolv.conf.backup; fi
            ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
            
            systemctl reload-or-restart systemd-resolved
            
            if lsof -i :53 | grep -q 'systemd-r'; then
                error "Failed to free port 53. Please resolve the issue manually."
                return 1
            else
                success "The conflict with systemd-resolved has been successfully resolved."
                return 0
            fi
        else
            error "Installation cannot proceed without freeing port 53."
            return 1
        fi
    fi
    return 0
}

# --- CONFIGURATION MANAGEMENT FUNCTIONS ---
# Saves the username, password hash, and network settings from the current configuration.
save_user_credentials() {
    if [ ! -f "$ADH_CONFIG_FILE" ]; then error "Configuration file not found: $ADH_CONFIG_FILE"; return 1; fi
    USER_NAME=$(yq eval '.users[0].name // "admin"' "$ADH_CONFIG_FILE"); USER_PASS_HASH=$(yq eval '.users[0].password // ""' "$ADH_CONFIG_FILE"); HTTP_ADDRESS=$(yq eval '.http.address // "0.0.0.0:80"' "$ADH_CONFIG_FILE"); DNS_BIND_HOST=$(yq eval '.dns.bind_hosts[0] // "0.0.0.0"' "$ADH_CONFIG_FILE"); DNS_PORT=$(yq eval '.dns.port // 53' "$ADH_CONFIG_FILE")
    if [ -z "$USER_NAME" ] || [ -z "$USER_PASS_HASH" ]; then
        info "No saved profile found. Default credentials set: login 'admin', password 'adminadmin'"
        USER_NAME="admin"; USER_PASS_HASH='$2a$10$ran/S7NMc.GAhm0ac3wTbuWV2LVLxfxwNg5xGZC0b5PHWsykOHxey';
    fi
}

# Applies the saved credentials and network settings to a new configuration file.
apply_user_credentials() {
    local target_file="$1"; if [ ! -f "$target_file" ]; then return 1; fi
    yq eval ".users[0].name = \"$USER_NAME\"" -i "$target_file"; yq eval ".users[0].password = \"$USER_PASS_HASH\"" -i "$target_file"; yq eval ".http.address = \"$HTTP_ADDRESS\"" -i "$target_file"; yq eval ".dns.bind_hosts[0] = \"$DNS_BIND_HOST\"" -i "$target_file"; yq eval ".dns.port = $DNS_PORT" -i "$target_file"
    if [ "$(yq eval '.users | length' "$target_file")" = "0" ]; then yq eval '.users = [{"name": "'"$USER_NAME"'", "password": "'"$USER_PASS_HASH"'"}]' -i "$target_file"; fi
}

# Creates a backup of the current user configuration.
create_user_backup() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return; fi
    if [ -f "$LOCAL_CONFIG_USER" ]; then if ! prompt_yes_no "A user backup already exists. Overwrite it?"; then info "Operation canceled."; return; fi; fi
    cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_USER"; success "Current configuration successfully saved to ${LOCAL_CONFIG_USER}"
}

# Sets a very long session TTL in the configuration file.
force_session_ttl() { yq eval '.http.session_ttl = "876000h"' -i "$1"; }
# Forcibly removes all remnants of a previous AdGuard Home installation.
force_cleanup_remnants() { systemctl stop "$ADH_SERVICE_NAME" &>/dev/null || true; systemctl disable "$ADH_SERVICE_NAME" &>/dev/null || true; rm -f "/etc/systemd/system/${ADH_SERVICE_NAME}" "/lib/systemd/system/${ADH_SERVICE_NAME}"; rm -rf "$ADH_DIR"; systemctl daemon-reload; }

# --- MAIN FUNCTIONS (MENU ITEMS) ---
# Installs AdGuard Home and performs the initial setup.
install_adh() {
    if is_adh_installed; then warning "AdGuard Home is already installed."; return; fi
    local service_file_exists=false; systemctl cat "$ADH_SERVICE_NAME" &>/dev/null && service_file_exists=true
    if [ -d "$ADH_DIR" ] || [ "$service_file_exists" = true ]; then error "Remnants of a previous installation were found."; if prompt_yes_no "Remove them to continue?"; then force_cleanup_remnants; else error "Installation cannot proceed."; return 1; fi; fi
    
    if ! check_and_fix_port_53; then return 1; fi
    
    backup_resolv_conf;
    local INSTALL_LOG; INSTALL_LOG=$(mktemp); info "Installation has started, please wait..."
    if ! curl -s -S -L "$ADH_INSTALL_SCRIPT_URL" | sh -s -- -v > "$INSTALL_LOG" 2>&1; then error "AdGuard Home installation failed:"; cat "$INSTALL_LOG"; rm -f "$INSTALL_LOG"; exit 1; fi
    rm -f "$INSTALL_LOG"; systemctl daemon-reload; success "AdGuard Home has been installed successfully!"
    
    local server_ip; server_ip=$(hostname -I | awk '{print $1}')
    printf "\n1. Go to the following URL in your browser to complete the initial setup:\n"
    if [ -n "$server_ip" ]; then echo -e "🔗 ${C_YELLOW}http://${server_ip}:3000${C_RESET}"; fi
    
    while true; do read -p "2. Once you have finished the setup, enter '1' to continue: " choice; if [[ "$choice" == "1" ]]; then if [ -f "$ADH_CONFIG_FILE" ]; then break; else warning "The configuration file has not been created yet. Please complete all steps in the web UI at the link above."; fi; else warning "Please complete the setup and enter '1'."; fi; done
    
    printf "\n"
    info "Saving the initial configuration..."
    mkdir -p "$ADH_BACKUP_DIR"
    cp "$ADH_CONFIG_FILE" "$ADH_CONFIG_BACKUP"
    cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_STD"
    success "Initial configuration saved!"
    
    curl -s -S -L -o "$LOCAL_CONFIG_RU" "$CONFIG_URL_RU" &>/dev/null || true
    curl -s -S -L -o "$LOCAL_CONFIG_EN" "$CONFIG_URL_EN" &>/dev/null || true
    save_user_credentials
    
    printf "\n"
    if prompt_yes_no "Replace the initial configuration with a pre-configured one?"; then
        printf "\n"
        while true; do printf "Choose a configuration:\n1. For Russian servers\n2. For international (non-Russian) servers\n"; read -p "Your choice [1-2]: " cfg_choice; if [[ "$cfg_choice" == "1" || "$cfg_choice" == "2" ]]; then break; else warning "Invalid input."; fi; done
        
        printf "\n"
        info "Applying configuration, please wait..."
        if [ "$cfg_choice" -eq 1 ]; then get_config "$CONFIG_URL_RU" "$LOCAL_CONFIG_RU"; else get_config "$CONFIG_URL_EN" "$LOCAL_CONFIG_EN"; fi
        apply_user_credentials "$ADH_CONFIG_FILE"
    fi

    force_session_ttl "$ADH_CONFIG_FILE"; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service; create_integration_services
    
    set +e; test_adh --silent; local test_result=$?; true; set -e
    if [ $test_result -eq 0 ]; then success "AdGuard Home is working successfully!"; else error "Failed to perform a DNS query through AdGuard Home."; fi
}

# Allows the user to change the current AdGuard Home configuration.
change_config() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return 1; fi
    while true; do
        printf "Select a configuration to apply:\n1. For Russian servers\n2. For international (non-Russian) servers\n3. Standard (created during initial setup)\n4. Restore from user backup\n5. Return to the main menu\n"
        read -p "Your choice [1-5]: " choice
        printf "\n"

        if [[ "$choice" =~ ^[1-5]$ ]]; then
            if [[ "$choice" -eq 5 ]]; then
                info "Returning to the main menu..."
                return 100
            fi
            break
        else
            warning "Invalid input."
            printf "\n"
        fi
    done
    
    save_user_credentials; info "Applying configuration..."
    case $choice in
        1) get_config "$CONFIG_URL_RU" "$LOCAL_CONFIG_RU" ;;
        2) get_config "$CONFIG_URL_EN" "$LOCAL_CONFIG_EN" ;;
        3) if [ -f "$LOCAL_CONFIG_STD" ]; then cp "$LOCAL_CONFIG_STD" "$ADH_CONFIG_FILE"; else error "Standard configuration file not found."; return 1; fi ;;
        4) if [ -f "$LOCAL_CONFIG_USER" ]; then cp "$LOCAL_CONFIG_USER" "$ADH_CONFIG_FILE"; else error "User backup not found."; return 1; fi ;;
    esac
    
    if [[ "$choice" == "1" || "$choice" == "2" ]]; then 
        apply_user_credentials "$ADH_CONFIG_FILE"
    fi
    
    force_session_ttl "$ADH_CONFIG_FILE"; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service
    success "Configuration applied successfully. Please verify AdGuard Home is working."
}

# Tests AdGuard Home functionality (name resolution, blocking, DNSSEC).
test_adh() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return 1; fi
    if [ "$1" == "--silent" ]; then set +e; dig @127.0.0.1 +time=2 +tries=2 +short ya.ru >/dev/null; local test_result=$?; true; set -e; return $test_result; fi

    info "Testing AdGuard Home functionality..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local all_tests_ok=true; local test_ok=false

    if dig @127.0.0.1 +time=2 +tries=2 ya.ru A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "1. ${C_GREEN}Success${C_RESET} resolving IP (ya.ru)\n"; else printf "1. ${C_RED}Failure${C_RESET} resolving IP (ya.ru)\n"; all_tests_ok=false; fi
    if dig @127.0.0.1 +time=2 +tries=2 google.com A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "2. ${C_GREEN}Success${C_RESET} resolving IP (google.com)\n"; else printf "2. ${C_RED}Failure${C_RESET} resolving IP (google.com)\n"; all_tests_ok=false; fi
    
    local ad_result; ad_result=$(dig @127.0.0.1 +time=2 +tries=2 doubleclick.net A +short)
    if [[ "$ad_result" == "0.0.0.0" || -z "$ad_result" ]]; then printf "3. ${C_GREEN}Success${C_RESET} blocking domain (doubleclick.net)\n"; else printf "3. ${C_RED}Failure${C_RESET} blocking domain (doubleclick.net)\n"; all_tests_ok=false; fi
    
    local dnssec_valid_domains=("www.internic.net" "www.dnssec-tools.org" "www.verisign.com" "www.nlnetlabs.nl"); test_ok=false
    for domain in "${dnssec_valid_domains[@]}"; do if dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec | grep -q "flags:.* ad;"; then printf "4. ${C_GREEN}Success${C_RESET} passed DNSSEC test (valid signature on %s)\n" "$domain"; test_ok=true; break; fi; done
    if ! $test_ok; then printf "4. ${C_RED}Failure${C_RESET} DNSSEC test (valid signature)\n"; all_tests_ok=false; fi

    local dnssec_invalid_domains=("dnssec-failed.org" "www.dnssec-failed.org" "brokendnssec.net" "dlv.isc.org"); test_ok=false
    for domain in "${dnssec_invalid_domains[@]}"; do
        set +e; local dnssec_fail_output; dnssec_fail_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec) ; true; set -e
        if [[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: SERVFAIL"* ]] || \
           ([[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* ]] && [[ "$dnssec_fail_output" != *"flags:.* ad;"* ]]); then
            printf "5. ${C_GREEN}Success${C_RESET} passed DNSSEC test (invalid signature on %s)\n" "$domain"
            test_ok=true
            break
        fi
    done
    if ! $test_ok; then printf "5. ${C_RED}Failure${C_RESET} DNSSEC test (invalid signature)\n"; all_tests_ok=false; fi
    
    local dnssec_insecure_domains=("example.com" "github.com" "iana.org" "icann.org"); test_ok=false
    for domain in "${dnssec_insecure_domains[@]}"; do
        local dnssec_insecure_output; dnssec_insecure_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec)
        if [[ "$dnssec_insecure_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* && "$dnssec_insecure_output" != *"flags:.* ad;"* ]]; then printf "6. ${C_GREEN}Success${C_RESET} passed DNSSEC test (insecure domain on %s)\n" "$domain"; test_ok=true; break; fi
    done
    if ! $test_ok; then printf "6. ${C_RED}Failure${C_RESET} DNSSEC test (insecure domain)\n"; all_tests_ok=false; fi

    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    if $all_tests_ok; then
        success "AdGuard Home is working correctly."
        return 0 
    else 
        error "There may be issues with AdGuard Home's functionality."
        if [ "$1" == "--silent" ]; then
            return 1
        else
            return 0
        fi
    fi
}

# Completely uninstalls AdGuard Home and all related files.
uninstall_adh() {
    if ! is_adh_installed && [ ! -d "$ADH_DIR" ]; then warning "AdGuard Home is not installed."; return; fi; local force_uninstall=false; if [ "$1" == "--force" ]; then force_uninstall=true; fi
    if ! $force_uninstall && ! prompt_yes_no "Are you sure you want to completely uninstall AdGuard Home?"; then info "Uninstallation canceled."; return 1; fi
    
    info "Uninstalling, please wait..."
    chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; if is_service_installed; then systemctl disable --now set-dns.service 2>/dev/null || true; rm -f "$SERVICE_FILE_PATH" "$SET_DNS_SCRIPT_PATH"; fi
    if [ -x "$ADH_DIR/AdGuardHome" ]; then "$ADH_DIR/AdGuardHome" -s uninstall &>/dev/null; fi
    force_cleanup_remnants; restore_resolv_conf; chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    success "AdGuard Home has been completely uninstalled!"
}

# Reinstalls AdGuard Home by performing an uninstall followed by an install.
reinstall_adh() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return; fi
    if ! prompt_yes_no "Are you sure you want to REINSTALL AdGuard Home?"; then info "Reinstallation canceled."; return 1; fi
    printf "\n"
    uninstall_adh --force
    printf "\n"
    install_adh
}

# Manages the AdGuard Home service (start, stop, restart, status).
manage_service() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return; fi
    set +e; systemctl "$1" "$ADH_SERVICE_NAME"; true; set -e
}

# Displays the main menu and handles user selection.
main_menu() {
    while true; do
        clear; local menu_items=(); local menu_actions=()
        printf "${C_GREEN}AdGuard Home Easy Setup by Internet Helper${C_RESET}\n"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if is_adh_installed; then if is_adh_active; then printf "${C_GREEN}🟢 Running${C_RESET}\n"; else printf "${C_YELLOW}🟡 Stopped${C_RESET}\n"; fi; else printf "${C_RED}🔴 Not Installed${C_RESET}\n"; fi
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; local group_counts=()
        if is_adh_installed; then
            menu_items+=("Start AdGuard Home" "Stop AdGuard Home" "Restart AdGuard Home" "Show AdGuard Home Status"); menu_actions+=("manage_service 'start'" "manage_service 'stop'" "manage_service 'restart'" "clear; manage_service 'status'"); group_counts+=(4)
            menu_items+=("Change Configuration" "Create User Backup" "Test Functionality"); menu_actions+=("change_config" "create_user_backup" "test_adh"); group_counts+=(3)
            menu_items+=("Reinstall" "Uninstall"); menu_actions+=("reinstall_adh" "uninstall_adh"); group_counts+=(2)
        else menu_items+=("Install AdGuard Home"); menu_actions+=("install_adh"); group_counts+=(1); fi
        local item_counter=0; for group_size in "${group_counts[@]}"; do for (( i=0; i<group_size; i++ )); do echo "$((item_counter+1)). ${menu_items[item_counter]}"; item_counter=$((item_counter+1)); done; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; done
        echo "0. Exit"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; read -p "Select an option: " menu_choice

        printf "\n"

        if [[ "$menu_choice" == "0" ]]; then exit 0; fi; if [[ ! "$menu_choice" =~ ^[0-9]+$ ]] || (( menu_choice < 1 || menu_choice > ${#menu_items[@]} )); then continue; fi
        
        local action_index=$((menu_choice - 1))
        
        set +e
        eval "${menu_actions[action_index]}"
        local return_code=$?
        true
        set -e
        
        if [[ "${menu_actions[action_index]}" != *"status"* && "${menu_actions[action_index]}" != *"manage_service"* && "$return_code" -ne 100 ]]; then
            printf "\n"; read -p "Press Enter to continue..."
        fi
    done
}

# --- SCRIPT ENTRY POINT ---
# Runs initial checks and displays the main menu.
initial_checks
main_menu