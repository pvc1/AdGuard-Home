#!/bin/bash

# AdGuard Home Easy Setup by Internet Helper v1.0 (Start)

# Exit script on any error, including pipe failures
set -e
set -o pipefail

# --- VARIABLES AND CONSTANTS ---

# Colors for output
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[38;2;0;210;106m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'

# Base paths
ADH_DIR="/opt/AdGuardHome"
ADH_DATA_DIR="${ADH_DIR}/data"
ADH_CONFIG_DIR="${ADH_DATA_DIR}/configs"

# Paths to files and system components
ADH_CONFIG_FILE="${ADH_DIR}/AdGuardHome.yaml"
ADH_CONFIG_BACKUP="${ADH_DIR}/AdGuardHome.yaml.initial_bak"
OVERWRITE_DNS_SCRIPT_PATH="${ADH_DATA_DIR}/overwrite-etc-resolv.sh"
SERVICE_FILE_PATH="/etc/systemd/system/set-dns.service"
RESOLV_CONF_PATH="/etc/resolv.conf"
RESOLV_BACKUP_PATH="/etc/resolv.conf.adh-backup"
ADH_SERVICE_NAME="AdGuardHome.service"
ADH_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"
REPO_URL="https://github.com/Internet-Helper/AdGuard-Home.git"

# Local paths to configuration files
LOCAL_CONFIG_STD="${ADH_CONFIG_DIR}/standard.yaml"
LOCAL_CONFIG_USER="${ADH_CONFIG_DIR}/user_backup.yaml"
LOCAL_CONFIG_RU_CLASSIC_ADS="${ADH_CONFIG_DIR}/ru_classic_ads.yaml"
LOCAL_CONFIG_RU_CLASSIC_NO_ADS="${ADH_CONFIG_DIR}/ru_classic_no_ads.yaml"
LOCAL_CONFIG_RU_PROXY_ADS="${ADH_CONFIG_DIR}/ru_proxy_ads.yaml"
LOCAL_CONFIG_RU_PROXY_NO_ADS="${ADH_CONFIG_DIR}/ru_proxy_no_ads.yaml"
LOCAL_CONFIG_EN_ADS="${ADH_CONFIG_DIR}/en_ads.yaml"
LOCAL_CONFIG_EN_NO_ADS="${ADH_CONFIG_DIR}/en_no_ads.yaml"

# Configuration URLs
CONFIG_URL_RU_CLASSIC_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/classic-dns/AdGuardHome.yaml"
CONFIG_URL_RU_CLASSIC_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/classic-dns/ad-filter-off/AdGuardHome.yaml"
CONFIG_URL_RU_PROXY_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/proxy-dns/AdGuardHome.yaml"
CONFIG_URL_RU_PROXY_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/proxy-dns/ad-filter-off/AdGuardHome.yaml"
CONFIG_URL_EN_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/english/AdGuardHome.yaml"
CONFIG_URL_EN_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/english/ad-filter-off/AdGuardHome.yaml"


# --- TRAP AND CLEANUP FUNCTIONS ---

# Traps script exit and performs a rollback on error.
handle_exit() {
    local EXIT_CODE=$?
    chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 130 ] && [ $EXIT_CODE -ne 100 ]; then
        printf "\n${C_RED}ERROR: Script exited with code %s.${C_RESET}\n" "$EXIT_CODE"
        printf "${C_YELLOW}Rolling back changes...${C_RESET}\n"; restore_resolv_conf; printf "${C_GREEN}Rollback complete.${C_RESET}\n"
    fi
}
# Traps script interruption (Ctrl+C) and performs a rollback.
handle_interrupt() {
    printf "\n\n${C_YELLOW}Script interrupted. Rolling back changes...${C_RESET}\n"
    restore_resolv_conf
    printf "${C_GREEN}Rollback complete.${C_RESET}\n"
    exit 130
}
trap 'handle_exit' EXIT; trap 'handle_interrupt' SIGINT SIGTERM SIGHUP

# --- HELPER FUNCTIONS ---

info() { printf "${C_GREEN}> %s${C_RESET}\n" "$1"; }
success() { printf "${C_GREEN}✓ %s${C_RESET}\n" "$1"; }
warning() { printf "${C_YELLOW}! %s${C_RESET}\n" "$1"; }
error() { printf "${C_RED}✗ %s${C_RESET}\n" "$1"; }

prompt_yes_no() {
    local prompt_text="$1"; local choice
    while true; do read -p "$prompt_text (1 - yes, 2 - no): " choice; case $choice in 1) return 0 ;; 2) return 1 ;; *) warning "Invalid input." ;; esac; done
}
wait_for_adh_service() {
    for i in {1..15}; do if systemctl is-active --quiet "$ADH_SERVICE_NAME"; then sleep 0.5; return 0; fi; sleep 1; done
    error "AdGuard Home service failed to start within 15 seconds."; return 1
}
is_adh_installed() { [ -f "$ADH_CONFIG_FILE" ] && systemctl cat "$ADH_SERVICE_NAME" &>/dev/null; }
is_service_installed() { [ -f "$SERVICE_FILE_PATH" ]; }
is_adh_active() { is_adh_installed && systemctl is-active --quiet "$ADH_SERVICE_NAME"; }
backup_resolv_conf() { if [ ! -f "$RESOLV_BACKUP_PATH" ]; then cp -p "$RESOLV_CONF_PATH" "$RESOLV_BACKUP_PATH"; fi; }
restore_resolv_conf() { if [ -f "$RESOLV_BACKUP_PATH" ]; then chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; cp -p "$RESOLV_BACKUP_PATH" "$RESOLV_CONF_PATH"; rm -f "$RESOLV_BACKUP_PATH"; fi; }

install_yq() {
    if [ ! -f "/usr/local/bin/yq" ]; then
        case "$(uname -m)" in x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; armv7l) ARCH="arm" ;; *) error "Unsupported architecture: $(uname -m)"; exit 1 ;; esac
        wget "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq && success "yq has been installed successfully!"
    fi
}

# Determines the best IP address to display in the menu
get_display_ip() {
    local ip_services=("ifconfig.me" "icanhazip.com" "api.ipify.org" "ipinfo.io/ip" "ident.me")
    local public_ip=""
    for service in "${ip_services[@]}"; do
        public_ip=$(curl -s --max-time 4 "https://${service}")
        if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$public_ip"; return 0; fi
    done
    local system_ip; system_ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
    if [[ -n "$system_ip" ]]; then echo "$system_ip"; return 0; fi
    hostname -I | awk '{print $1}'
}

# --- Checks system, permissions, and installs dependencies ---
initial_checks() {
    if [ "$EUID" -ne 0 ]; then error "This script must be run as root (or with sudo)."; exit 1; fi
    
    local HTPASSWD_PACKAGE
    if [ -f /etc/os-release ]; then 
        . /etc/os-release
        case "$ID" in 
            debian|ubuntu) 
                PKG_UPDATER="apt-get update -y"; PKG_INSTALLER="apt-get install -y"
                DNS_PACKAGE="dnsutils"; HTPASSWD_PACKAGE="apache2-utils" ;;
            centos|almalinux|rocky|fedora) 
                PKG_UPDATER=""; 
                if [ "$ID" = "fedora" ]; then PKG_INSTALLER="dnf install -y"; else PKG_INSTALLER="yum install -y"; fi
                DNS_PACKAGE="bind-utils"; HTPASSWD_PACKAGE="httpd-tools" ;;
            *) 
                error "Unsupported operating system: $ID"; exit 1 ;;
        esac
    else 
        error "Could not determine the operating system."; exit 1
    fi
    
    local dependencies=("curl" "systemctl" "chattr" "logname" "tee" "grep" "awk" "sed" "hostname" "yq" "lsof" "git" "htpasswd")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            if [ -n "$PKG_UPDATER" ]; then $PKG_UPDATER &>/dev/null; fi
            case "$cmd" in
                yq) warning "yq not found. Installing..."; install_yq ;;
                git) warning "git not found. Installing..."; $PKG_INSTALLER git &>/dev/null; success "'git' has been installed successfully!" ;;
                htpasswd) warning "htpasswd not found. Installing..."; $PKG_INSTALLER "$HTPASSWD_PACKAGE" &>/dev/null; success "'htpasswd' has been installed successfully!" ;;
                *) error "Required utility '$cmd' not found."; exit 1 ;;
            esac
        fi
    done

    if ! command -v dig &>/dev/null; then 
        warning "'dig' is required for advanced DNS checks. Installing..."
        if [ -n "$PKG_UPDATER" ]; then $PKG_UPDATER &>/dev/null; fi
        $PKG_INSTALLER $DNS_PACKAGE &>/dev/null
        success "'dig' has been installed successfully!"
    fi
}

# --- Downloads all configuration files if they are missing locally ---
download_all_configs_if_missing() {
    mkdir -p "$ADH_CONFIG_DIR"; info "Checking and downloading local configuration files..."
    declare -A configs=( ["$LOCAL_CONFIG_RU_CLASSIC_ADS"]="$CONFIG_URL_RU_CLASSIC_ADS" ["$LOCAL_CONFIG_RU_CLASSIC_NO_ADS"]="$CONFIG_URL_RU_CLASSIC_NO_ADS" ["$LOCAL_CONFIG_RU_PROXY_ADS"]="$CONFIG_URL_RU_PROXY_ADS" ["$LOCAL_CONFIG_RU_PROXY_NO_ADS"]="$CONFIG_URL_RU_PROXY_NO_ADS" ["$LOCAL_CONFIG_EN_ADS"]="$CONFIG_URL_EN_ADS" ["$LOCAL_CONFIG_EN_NO_ADS"]="$CONFIG_URL_EN_NO_ADS" )
    local all_files_exist=true
    for local_path in "${!configs[@]}"; do if [ ! -f "$local_path" ]; then all_files_exist=false; if ! curl -s -S -L -o "$local_path" "${configs[$local_path]}"; then error "Failed to download ${configs[$local_path]}"; fi; fi; done
    if [ "$all_files_exist" = true ]; then success "All configuration files are in place."; else success "Download of missing files is complete."; fi
}

# --- Updates and applies the selected configuration ---
update_and_apply_config() {
    local remote_url="$1"; local local_path="$2"
    if ! curl -s -S -L -o "$local_path" "$remote_url"; then warning "Failed to update '${basename "$local_path"}'. Using existing local copy."; fi
    if [ -f "$local_path" ]; then cp "$local_path" "$ADH_CONFIG_FILE"; else error "Critical error: configuration file is missing and cannot be downloaded."; return 1; fi
}

# --- Creates a script and service for system integration ---
create_integration_services() {
    cat > "$OVERWRITE_DNS_SCRIPT_PATH" << 'EOF'
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
    chmod +x "$OVERWRITE_DNS_SCRIPT_PATH"
    cat > "$SERVICE_FILE_PATH" << EOF
[Unit]
Description=Set DNS to AdGuard Home (127.0.0.1)
After=network-online.target ${ADH_SERVICE_NAME}
Wants=network-online.target
Requires=${ADH_SERVICE_NAME}
[Service]
Type=oneshot
ExecStart=${OVERWRITE_DNS_SCRIPT_PATH}
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; if ! systemctl enable --now set-dns.service >/dev/null 2>&1; then return 1; fi
}

# --- Checks for and resolves port 53 conflict with systemd-resolved ---
check_and_fix_port_53() {
    if lsof -i :53 | grep -q 'systemd-r'; then
        warning "Conflict detected: port 53 is occupied by the systemd-resolved service."
        if prompt_yes_no "Do you want the script to automatically free this port?"; then
            info "Applying fix for systemd-resolved..."; mkdir -p /etc/systemd/resolved.conf.d
            cat > /etc/systemd/resolved.conf.d/adguardhome.conf <<EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
            if [ -f /etc/resolv.conf ]; then mv /etc/resolv.conf /etc/resolv.conf.backup; fi; ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf; systemctl reload-or-restart systemd-resolved
            if lsof -i :53 | grep -q 'systemd-r'; then error "Failed to free port 53. Please resolve the issue manually."; return 1; else success "Conflict with systemd-resolved has been successfully resolved."; return 0; fi
        else error "Installation is not possible without freeing port 53."; return 1; fi
    fi; return 0
}

# --- Saves and applies user credentials ---
save_user_credentials() {
    if [ ! -f "$ADH_CONFIG_FILE" ]; then error "Configuration file not found: $ADH_CONFIG_FILE"; return 1; fi
    USER_NAME=$(yq eval '.users[0].name' "$ADH_CONFIG_FILE"); USER_PASS_HASH=$(yq eval '.users[0].password' "$ADH_CONFIG_FILE"); HTTP_ADDRESS=$(yq eval '.http.address' "$ADH_CONFIG_FILE"); DNS_BIND_HOST=$(yq eval '.dns.bind_hosts[0] // "0.0.0.0"' "$ADH_CONFIG_FILE"); DNS_PORT=$(yq eval '.dns.port // 53' "$ADH_CONFIG_FILE")
    if [ "$USER_NAME" = "null" ] || [ -z "$USER_NAME" ] || [ "$USER_PASS_HASH" = "null" ] || [ -z "$USER_PASS_HASH" ]; then
        info "Credentials not found. A new user must be created."; local NEW_USER_NAME=""; local NEW_USER_PASS=""
        while [ -z "$NEW_USER_NAME" ]; do read -p "Please enter a new username: " NEW_USER_NAME; done
        while [ -z "$NEW_USER_PASS" ]; do read -s -p "Please enter a new password: " NEW_USER_PASS; printf "\n"; done
        USER_NAME="$NEW_USER_NAME"; unset USER_PASS_HASH; USER_PASS_PLAIN="$NEW_USER_PASS"; success "New credentials accepted."
    fi
}
apply_user_credentials() {
    local target_file="$1"; if [ ! -f "$target_file" ]; then return 1; fi; local password_value; if [ -n "$USER_PASS_HASH" ]; then password_value="$USER_PASS_HASH"; elif [ -n "$USER_PASS_PLAIN" ]; then password_value="$USER_PASS_PLAIN"; else error "Could not determine the password to apply."; return 1; fi
    yq eval ".users[0].name = \"$USER_NAME\"" -i "$target_file"; yq eval ".users[0].password = \"$password_value\"" -i "$target_file"; yq eval ".http.address = \"$HTTP_ADDRESS\"" -i "$target_file"; yq eval ".dns.bind_hosts[0] = \"$DNS_BIND_HOST\"" -i "$target_file"; yq eval ".dns.port = $DNS_PORT" -i "$target_file"
    if [ "$(yq eval '.users | length' "$target_file")" == "0" ]; then yq eval '.users = [{"name": "'"$USER_NAME"'", "password": "'"$password_value"'"}]' -i "$target_file"; fi
}

# --- Creates a backup of the current user configuration ---
create_user_backup() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return; fi
    if [ -f "$LOCAL_CONFIG_USER" ]; then if ! prompt_yes_no "A user backup already exists. Overwrite it?"; then info "Operation canceled."; return; fi; fi
    cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_USER"; success "Current configuration successfully saved to ${LOCAL_CONFIG_USER}"
}
force_session_ttl() { yq eval '.http.session_ttl = "876000h"' -i "$1"; }
force_cleanup_remnants() { systemctl stop "$ADH_SERVICE_NAME" &>/dev/null || true; systemctl disable "$ADH_SERVICE_NAME" &>/dev/null || true; rm -f "/etc/systemd/system/${ADH_SERVICE_NAME}" "/lib/systemd/system/${ADH_SERVICE_NAME}"; rm -rf "$ADH_DIR"; systemctl daemon-reload; }


# --- Function to check AdGuard Home after installation ---
check_adh_post_install() {
    info "Checking service startup and DNS..."
    sleep 3 # A short pause to allow the service to initialize

    # Disable exit on error for the test
    set +e
    test_adh --silent
    local test_result=$?
    # Re-enable exit on error
    set -e

    if [ $test_result -eq 0 ]; then
        success "AdGuard Home is working successfully!"
    else
        warning "Initial test failed (code: $test_result). Rerunning check..."
        sleep 5

        set +e
        test_adh --silent
        test_result=$?
        set -e
        
        if [ $test_result -eq 0 ]; then
            success "AdGuard Home is working successfully!"
        else
            error "Could not confirm AdGuard Home service startup (code: $test_result)."
            warning "The service may need more time to load filter lists."
            warning "Please check the status in the main menu or test manually later."
            # Return a special code so the main menu doesn't prompt "Press Enter"
            return 100
        fi
    fi
}

# --- Installs AdGuard Home and performs initial setup ---
install_adh() {
    if is_adh_installed; then warning "AdGuard Home is already installed."; return; fi
    local service_file_exists=false; systemctl cat "$ADH_SERVICE_NAME" &>/dev/null && service_file_exists=true
    if [ -d "$ADH_DIR" ] || [ "$service_file_exists" = true ]; then error "Remnants of a previous installation detected."; if prompt_yes_no "Delete them to continue?"; then force_cleanup_remnants; else error "Installation is not possible."; return 1; fi; fi
    if ! check_and_fix_port_53; then return 1; fi
    
    backup_resolv_conf; local INSTALL_LOG; INSTALL_LOG=$(mktemp); info "Installation has started, please wait..."
    if ! curl -s -S -L "$ADH_INSTALL_SCRIPT_URL" | sh -s -- -v > "$INSTALL_LOG" 2>&1; then
        if grep -q "existing AdGuard Home installation is detected" "$INSTALL_LOG"; then
            warning "Official installer detected remnants. Forcing cleanup..."; uninstall_adh --force
            info "Cleanup complete. Retrying installation...";
            if ! curl -s -S -L "$ADH_INSTALL_SCRIPT_URL" | sh -s -- -v > "$INSTALL_LOG" 2>&1; then error "Re-installation of AdGuard Home also failed:"; cat "$INSTALL_LOG"; rm -f "$INSTALL_LOG"; exit 1; fi
        else error "AdGuard Home installation failed:"; cat "$INSTALL_LOG"; rm -f "$INSTALL_LOG"; exit 1; fi
    fi
    rm -f "$INSTALL_LOG"; systemctl daemon-reload; success "AdGuard Home has been installed successfully!"
    
    local server_ip; server_ip=$(hostname -I | awk '{print $1}'); printf "\n1. Open the link below in your browser and complete the initial setup:\n"; if [ -n "$server_ip" ]; then echo -e "🔗 ${C_YELLOW}http://${server_ip}:3000${C_RESET}"; fi
    local choice; while true; do read -p "2. When you are finished with the setup, enter '1' to continue: " choice; if [[ "$choice" == "1" ]]; then if [ -f "$ADH_CONFIG_FILE" ]; then break; else warning "The configuration file has not been created yet. Please complete all steps in the web UI."; fi; else warning "Please complete the setup and enter '1'."; fi; done
    
    download_all_configs_if_missing
    
    printf "\n"; info "Saving default configuration..."; mkdir -p "$ADH_CONFIG_DIR"; cp "$ADH_CONFIG_FILE" "$ADH_CONFIG_BACKUP"; cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_STD"; success "Default configuration saved!"
    save_user_credentials
    
    printf "\n"
    if prompt_yes_no "Replace the default configuration with a pre-configured one?"; then
        printf "\n"; local cfg_choice; while true; do printf "Select a configuration:\n1. For Russian servers\n2. For international servers\n"; read -p "Your choice [1-2]: " cfg_choice; if [[ "$cfg_choice" == "1" || "$cfg_choice" == "2" ]]; then break; else warning "Invalid input."; fi; done
        local remote_url; local local_path
        if [ "$cfg_choice" -eq 1 ]; then
            local use_proxy=false; if prompt_yes_no "Use DNS proxy to bypass geo-blocking?"; then use_proxy=true; fi
            local use_ad_blocking=false; if prompt_yes_no "Enable ad blocking?"; then use_ad_blocking=true; fi
            if [ "$use_proxy" = true ]; then
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_PROXY_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_ADS"; else remote_url="$CONFIG_URL_RU_PROXY_NO_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_NO_ADS"; fi
            else
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_CLASSIC_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_ADS"; else remote_url="$CONFIG_URL_RU_CLASSIC_NO_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_NO_ADS"; fi
            fi
        else
            if prompt_yes_no "Enable ad blocking?"; then remote_url="$CONFIG_URL_EN_ADS"; local_path="$LOCAL_CONFIG_EN_ADS"; else remote_url="$CONFIG_URL_EN_NO_ADS"; local_path="$LOCAL_CONFIG_EN_NO_ADS"; fi
        fi
        printf "\n"; info "Applying selected configuration..."; update_and_apply_config "$remote_url" "$local_path"; apply_user_credentials "$ADH_CONFIG_FILE"
    fi

    force_session_ttl "$ADH_CONFIG_FILE";
    systemctl restart "$ADH_SERVICE_NAME";
    wait_for_adh_service;
    create_integration_services
    check_adh_post_install
}

# --- Allows the user to change the current AdGuard Home configuration ---
change_config() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return 1; fi
    
    local menu_prompt
    menu_prompt="Select a configuration to apply:"
    menu_prompt+="\n1. For Russian servers"
    menu_prompt+="\n2. For international servers"
    menu_prompt+="\n3. Default (created during installation)"
    menu_prompt+="\n4. Restore from user backup"
    menu_prompt+="\n5. Return to main menu\n"

    local menu_choice
    while true; do 
        printf "%b" "$menu_prompt"
        read -p "Your choice [1-5]: " menu_choice
        if [[ "$menu_choice" =~ ^[1-5]$ ]]; then 
            if [[ "$menu_choice" -eq 5 ]]; then 
                info "Returning to main menu..."
                return 100
            fi
            break
        else 
            warning "Invalid input."
        fi
    done

    # Save current credentials BEFORE any changes
    save_user_credentials
    local should_apply_credentials=false

    case $menu_choice in
        1) 
            local use_proxy=false; if prompt_yes_no "Use DNS proxy to bypass geo-blocking?"; then use_proxy=true; fi
            local use_ad_blocking=false; if prompt_yes_no "Enable ad blocking?"; then use_ad_blocking=true; fi
            if [ "$use_proxy" = true ]; then
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_PROXY_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_ADS"; else remote_url="$CONFIG_URL_RU_PROXY_NO_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_NO_ADS"; fi
            else
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_CLASSIC_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_ADS"; else remote_url="$CONFIG_URL_RU_CLASSIC_NO_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_NO_ADS"; fi
            fi
            info "Applying configuration for Russian servers..."; update_and_apply_config "$remote_url" "$local_path"
            should_apply_credentials=true 
            ;;
        2) 
            if prompt_yes_no "Enable ad blocking?"; then remote_url="$CONFIG_URL_EN_ADS"; local_path="$LOCAL_CONFIG_EN_ADS"; else remote_url="$CONFIG_URL_EN_NO_ADS"; local_path="$LOCAL_CONFIG_EN_NO_ADS"; fi
            info "Applying configuration for international servers..."; update_and_apply_config "$remote_url" "$local_path"
            should_apply_credentials=true 
            ;;
        3) 
            if [ -f "$LOCAL_CONFIG_STD" ]; then 
                cp "$LOCAL_CONFIG_STD" "$ADH_CONFIG_FILE"
                success "Default configuration has been restored."
                should_apply_credentials=true
            else 
                error "Default configuration file not found."
                return 1
            fi 
            ;;
        4) 
            if [ -f "$LOCAL_CONFIG_USER" ]; then 
                cp "$LOCAL_CONFIG_USER" "$ADH_CONFIG_FILE"
                success "Configuration has been restored from user backup."
                should_apply_credentials=true
            else 
                error "User backup not found."
                return 1
            fi 
            ;;
    esac

    # This logic now runs for ALL options (1, 2, 3, and 4)
    if [ "$should_apply_credentials" = true ]; then 
        apply_user_credentials "$ADH_CONFIG_FILE"
    fi

    force_session_ttl "$ADH_CONFIG_FILE"
    systemctl restart "$ADH_SERVICE_NAME"
    wait_for_adh_service
    success "Configuration applied successfully. Please verify that AdGuard Home is working."
}

# --- Allows the user to change the web interface or DNS service address ---
change_address_menu() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return 1; fi
    local menu_choice; while true; do printf "Which address do you want to change?\n1. Web interface address\n2. DNS service address\n3. Return to main menu\n"; read -p "Your choice [1-3]: " menu_choice; if [[ "$menu_choice" =~ ^[1-3]$ ]]; then break; else warning "Invalid input."; fi; done
    if [[ "$menu_choice" -eq 3 ]]; then return 100; fi

    mapfile -t available_ips < <(ip -4 -o addr show | awk '{print $4}' | cut -d'/' -f1)
    local choices=("0.0.0.0 (on all interfaces)")
    for ip in "${available_ips[@]}"; do choices+=("$ip"); done
    
    printf "\nSelect an IP address from the list:\n\n"
    
    local i=1
    for item in "${choices[@]}"; do
        printf "%s) %s\n" "$i" "$item"
        ((i++))
    done
    
    printf "\n"

    local num_choices=${#choices[@]}
    local ip_choice
    local selected_ip
    
    while true; do
        read -p "Your choice [1-${num_choices}]: " ip_choice
        if [[ "$ip_choice" =~ ^[0-9]+$ ]] && [ "$ip_choice" -ge 1 ] && [ "$ip_choice" -le "$num_choices" ]; then
            selected_ip=${choices[$((ip_choice - 1))]}
            selected_ip=$(echo "$selected_ip" | awk '{print $1}')
            break
        else
            warning "Invalid input."
        fi
    done
    
    if [ "$menu_choice" -eq 1 ]; then
        local port; while true; do
            printf "\n"
            read -p "Enter a new port for the web interface (e.g., 8080): " port
            if ! [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
                warning "Please enter a valid port number (1-65535)."
                continue
            fi
            
            local pid
            pid=$(lsof -t -i :"$port" 2>/dev/null | head -n 1)

            if [ -n "$pid" ]; then
                local process_name
                process_name=$(ps -p "$pid" -o comm=)
                
                if [[ "$process_name" != "AdGuardHome" ]]; then
                    error "Port $port is already in use by process '${process_name}'. Please choose another one."
                    continue
                fi
            fi
            
            break
        done
        printf "\n"
        yq eval ".http.address = \"${selected_ip}:${port}\"" -i "$ADH_CONFIG_FILE"
    else
        printf "\n"
        yq eval ".dns.bind_hosts[0] = \"$selected_ip\"" -i "$ADH_CONFIG_FILE"
    fi
    info "Restarting AdGuard Home to apply changes..."; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service
    success "Address changed successfully!"
}

# --- Allows the user to change the username and password ---
change_credentials() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return 1; fi

    if ! prompt_yes_no "Do you want to change the username and password?"; then
        info "Operation canceled."
        return 100
    fi
    printf "\n"

    local new_user; local new_pass
    local valid_chars='^[A-Za-z0-9_.-]+$'

    while true; do
        read -p "Enter a new username: " new_user
        if [[ "$new_user" =~ $valid_chars ]]; then break; else error "Username can only contain Latin letters, numbers, dots, hyphens, and underscores."; fi
    done
    
    if prompt_yes_no "Generate a random, secure password?"; then
        new_pass=$(tr -dc 'A-Za-z0-9_!@#$%^&*' < /dev/urandom | head -c 64)
        printf "\n"
        printf "Save the new password: ${C_YELLOW}%s${C_RESET}\n" "$new_pass"
        printf "\n"
    fi
    
    while [ -z "$new_pass" ]; do
        read -s -p "Enter a new password (minimum 6 characters): " new_pass; printf "\n"
        if [[ ! "$new_pass" =~ ^[A-Za-z0-9\_\.\!\@\#\$\%\^\&\*\(\)\+\=\-]+$ ]]; then
            error "Password can only contain Latin letters, numbers, and the following symbols: _ . ! @ # $ % ^ & * ( ) + = -"
            new_pass=""
        elif [ ${#new_pass} -lt 6 ]; then
            error "Password must be at least 6 characters long."
            new_pass=""
        fi
    done
    
    info "Changing credentials..."
    
    local NEW_PASS_HASH
    NEW_PASS_HASH=$(htpasswd -nbB -C 10 "tempuser" "$new_pass" | cut -d':' -f2)

    if [[ -z "$NEW_PASS_HASH" ]]; then
        error "Failed to generate password hash. Update canceled."
        return 1
    fi

    systemctl stop "$ADH_SERVICE_NAME"

    yq eval ".users[0].name = \"$new_user\"" -i "$ADH_CONFIG_FILE"
    yq eval ".users[0].password = \"$NEW_PASS_HASH\"" -i "$ADH_CONFIG_FILE"
    
    info "Starting AdGuard Home..."; systemctl start "$ADH_SERVICE_NAME"; wait_for_adh_service
    success "Credentials changed successfully."
}

# --- Tests AdGuard Home functionality ---
test_adh() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return 1; fi
    if [ "$1" == "--silent" ]; then set +e; dig @127.0.0.1 +time=2 +tries=2 +short ya.ru >/dev/null; local test_result=$?; true; set -e; return $test_result; fi
    set +e; info "Testing AdGuard Home functionality..."; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; local all_tests_ok=true
    if dig @127.0.0.1 +time=2 +tries=2 ya.ru A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "1. ${C_GREEN}Success${C_RESET} resolved IP for (ya.ru)\n"; else printf "1. ${C_RED}Failure${C_RESET} to resolve IP for (ya.ru)\n"; all_tests_ok=false; fi
    if dig @127.0.0.1 +time=2 +tries=2 google.com A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "2. ${C_GREEN}Success${C_RESET} resolved IP for (google.com)\n"; else printf "2. ${C_RED}Failure${C_RESET} to resolve IP for (google.com)\n"; all_tests_ok=false; fi
    local ad_result; ad_result=$(dig @127.0.0.1 +time=2 +tries=2 doubleclick.net A +short); if [[ "$ad_result" == "0.0.0.0" || -z "$ad_result" ]]; then printf "3. ${C_GREEN}Success${C_RESET} blocked ad domain (doubleclick.net)\n"; else printf "3. ${C_RED}Failure${C_RESET} to block ad domain (doubleclick.net)\n"; all_tests_ok=false; fi
    local test_ok=false; local dnssec_valid_domains=("www.internic.net" "www.dnssec-tools.org" "www.verisign.com" "www.nlnetlabs.nl"); for domain in "${dnssec_valid_domains[@]}"; do if dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec | grep -q "flags:.* ad;"; then printf "4. ${C_GREEN}Success${C_RESET} passed DNSSEC (valid signature for %s)\n" "$domain"; test_ok=true; break; fi; done; if ! $test_ok; then printf "4. ${C_RED}Failure${C_RESET} DNSSEC (valid signature)\n"; all_tests_ok=false; fi
    test_ok=false; local dnssec_invalid_domains=("dnssec-failed.org" "www.dnssec-failed.org" "brokendnssec.net" "dlv.isc.org"); for domain in "${dnssec_invalid_domains[@]}"; do local dnssec_fail_output; dnssec_fail_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec); if [[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: SERVFAIL"* ]] || ([[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* ]] && [[ "$dnssec_fail_output" != *"flags:.* ad;"* ]]); then printf "5. ${C_GREEN}Success${C_RESET} passed DNSSEC (invalid signature for %s)\n" "$domain"; test_ok=true; break; fi; done; if ! $test_ok; then printf "5. ${C_RED}Failure${C_RESET} DNSSEC (invalid signature)\n"; all_tests_ok=false; fi
    test_ok=false; local dnssec_insecure_domains=("example.com" "github.com" "iana.org" "icann.org"); for domain in "${dnssec_insecure_domains[@]}"; do local dnssec_insecure_output; dnssec_insecure_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec); if [[ "$dnssec_insecure_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* && "$dnssec_insecure_output" != *"flags:.* ad;"* ]]; then printf "6. ${C_GREEN}Success${C_RESET} passed DNSSEC (insecure domain %s)\n" "$domain"; test_ok=true; break; fi; done; if ! $test_ok; then printf "6. ${C_RED}Failure${C_RESET} DNSSEC (insecure domain)\n"; all_tests_ok=false; fi
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; set -e; return 0
}

# --- Completely uninstalls AdGuard Home and all related files ---
uninstall_adh() {
    if ! is_adh_installed && [ ! -d "$ADH_DIR" ]; then warning "AdGuard Home is not installed."; return; fi
    local force_uninstall=false; if [ "$1" == "--force" ]; then force_uninstall=true; fi
    if ! $force_uninstall && ! prompt_yes_no "Are you sure you want to completely uninstall AdGuard Home?"; then info "Uninstall canceled."; return 1; fi
    info "Uninstalling, please wait..."; chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    if is_service_installed; then systemctl disable --now set-dns.service 2>/dev/null || true; rm -f "$SERVICE_FILE_PATH" "$OVERWRITE_DNS_SCRIPT_PATH"; fi
    if [ -x "$ADH_DIR/AdGuardHome" ]; then "$ADH_DIR/AdGuardHome" -s uninstall &>/dev/null; fi
    force_cleanup_remnants; restore_resolv_conf; chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; success "AdGuard Home has been completely uninstalled!"
}

# --- Reinstalls AdGuard Home ---
reinstall_adh() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return; fi
    if ! prompt_yes_no "Are you sure you want to REINSTALL AdGuard Home?"; then info "Reinstall canceled."; return 1; fi
    printf "\n"; uninstall_adh --force; printf "\n"; install_adh
}

# --- Manages the AdGuard Home service ---
manage_service() {
    if ! is_adh_installed; then error "AdGuard Home is not installed."; return; fi
    set +e; systemctl "$1" "$ADH_SERVICE_NAME"; true; set -e
}

# --- Displays the main menu and handles user selection ---
main_menu() {
    while true; do
        clear;
        printf "${C_GREEN}AdGuard Home Easy Setup by Internet Helper${C_RESET}\n"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if is_adh_installed; then
           local web_address; web_address=$(yq eval '.http.address' "$ADH_CONFIG_FILE" 2>/dev/null)
           local ip_part; ip_part=$(echo "$web_address" | cut -d':' -f1); local port_part; port_part=$(echo "$web_address" | cut -d':' -f2)
           local display_url
           if [[ "$ip_part" == "0.0.0.0" ]]; then local display_ip; display_ip=$(get_display_ip); display_url="http://${display_ip}:${port_part}"; else display_url="http://${web_address}"; fi
           if is_adh_active; then printf "⚙️  Status: \n${C_GREEN}🟢 Running at %s${C_RESET}\n" "$display_url"; else printf "⚙️  Status:\n${C_YELLOW}🟡 Stopped at %s${C_RESET}\n" "$display_url"; fi
        else
           printf "${C_RED}🔴 Status: Not Installed${C_RESET}\n"
        fi
        
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if is_adh_installed; then
            printf "1. Start AdGuard Home\n2. Stop AdGuard Home\n3. Restart AdGuard Home\n"
            printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            printf "4. Change Configuration\n5. Change Address\n6. Change Credentials\n"
            printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            printf "7. Create Backup\n8. Test Functionality\n"
            printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            printf "9. Reinstall\n10. Uninstall\n"
        else
            printf "1. Install AdGuard Home\n"
        fi
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; echo "0. Exit"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        local menu_choice; read -p "Select an action: " menu_choice; printf "\n"
        if [[ "$menu_choice" == "0" ]]; then exit 0; fi

        local action_to_run=""
        if is_adh_installed; then
            case $menu_choice in
                1) action_to_run="manage_service 'start'" ;; 2) action_to_run="manage_service 'stop'" ;; 3) action_to_run="manage_service 'restart'" ;;
                4) action_to_run="change_config" ;; 5) action_to_run="change_address_menu" ;; 6) action_to_run="change_credentials" ;;
                7) action_to_run="create_user_backup" ;; 8) action_to_run="test_adh" ;;
                9) action_to_run="reinstall_adh" ;; 10) action_to_run="uninstall_adh" ;;
                *) continue ;;
            esac
        else
            if [[ "$menu_choice" == "1" ]]; then action_to_run="install_adh"; else continue; fi
        fi

        set +e; eval "$action_to_run"; local return_code=$?; true; set -e
        if [[ "$action_to_run" != *"manage_service"* && "$return_code" -ne 100 ]]; then printf "\n"; read -p "Press Enter to continue..."; fi
    done
}

# --- SCRIPT ENTRY POINT ---
initial_checks
main_menu