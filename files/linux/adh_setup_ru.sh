#!/bin/bash

# AdGuard Home Easy Setup by Internet Helper v1.0 (Start)

# Выход из скрипта при любой ошибке, включая ошибки в конвейерах (pipes)
set -e
set -o pipefail

# --- ПЕРЕМЕННЫЕ И КОНСТАНТЫ ---

# Цвета для вывода
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[38;2;0;210;106m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'

# Базовые пути
ADH_DIR="/opt/AdGuardHome"
ADH_DATA_DIR="${ADH_DIR}/data"
ADH_CONFIG_DIR="${ADH_DATA_DIR}/configs"

# Пути к файлам и системным компонентам
ADH_CONFIG_FILE="${ADH_DIR}/AdGuardHome.yaml"
ADH_CONFIG_BACKUP="${ADH_DIR}/AdGuardHome.yaml.initial_bak"
OVERWRITE_DNS_SCRIPT_PATH="${ADH_DATA_DIR}/overwrite-etc-resolv.sh"
SERVICE_FILE_PATH="/etc/systemd/system/set-dns.service"
RESOLV_CONF_PATH="/etc/resolv.conf"
RESOLV_BACKUP_PATH="/etc/resolv.conf.adh-backup"
ADH_SERVICE_NAME="AdGuardHome.service"
ADH_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"
REPO_URL="https://github.com/Internet-Helper/AdGuard-Home.git"

# Локальные пути к файлам конфигураций
LOCAL_CONFIG_STD="${ADH_CONFIG_DIR}/standard.yaml"
LOCAL_CONFIG_USER="${ADH_CONFIG_DIR}/user_backup.yaml"
LOCAL_CONFIG_RU_CLASSIC_ADS="${ADH_CONFIG_DIR}/ru_classic_ads.yaml"
LOCAL_CONFIG_RU_CLASSIC_NO_ADS="${ADH_CONFIG_DIR}/ru_classic_no_ads.yaml"
LOCAL_CONFIG_RU_PROXY_ADS="${ADH_CONFIG_DIR}/ru_proxy_ads.yaml"
LOCAL_CONFIG_RU_PROXY_NO_ADS="${ADH_CONFIG_DIR}/ru_proxy_no_ads.yaml"
LOCAL_CONFIG_EN_ADS="${ADH_CONFIG_DIR}/en_ads.yaml"
LOCAL_CONFIG_EN_NO_ADS="${ADH_CONFIG_DIR}/en_no_ads.yaml"

# URL конфигураций
CONFIG_URL_RU_CLASSIC_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/classic-dns/AdGuardHome.yaml"
CONFIG_URL_RU_CLASSIC_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/classic-dns/ad-filter-off/AdGuardHome.yaml"
CONFIG_URL_RU_PROXY_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/proxy-dns/AdGuardHome.yaml"
CONFIG_URL_RU_PROXY_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/proxy-dns/ad-filter-off/AdGuardHome.yaml"
CONFIG_URL_EN_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/english/AdGuardHome.yaml"
CONFIG_URL_EN_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/english/ad-filter-off/AdGuardHome.yaml"


# --- ФУНКЦИИ-ПЕРЕХВАТЧИКИ И ОЧИСТКИ ---

# Перехватывает завершение скрипта и выполняет откат при ошибке.
handle_exit() {
    local EXIT_CODE=$?
    chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 130 ] && [ $EXIT_CODE -ne 100 ]; then
        printf "\n${C_RED}ОШИБКА: Скрипт завершился с кодом %s.${C_RESET}\n" "$EXIT_CODE"
        printf "${C_YELLOW}Выполняется откат изменений...${C_RESET}\n"; restore_resolv_conf; printf "${C_GREEN}Откат завершен.${C_RESET}\n"
    fi
}
# Перехватывает прерывание скрипта (Ctrl+C) и выполняет откат.
handle_interrupt() {
    printf "\n\n${C_YELLOW}Скрипт прерван. Выполняется откат изменений...${C_RESET}\n"
    restore_resolv_conf
    printf "${C_GREEN}Откат завершен.${C_RESET}\n"
    exit 130
}
trap 'handle_exit' EXIT; trap 'handle_interrupt' SIGINT SIGTERM SIGHUP

# --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---

info() { printf "${C_GREEN}> %s${C_RESET}\n" "$1"; }
success() { printf "${C_GREEN}✓ %s${C_RESET}\n" "$1"; }
warning() { printf "${C_YELLOW}! %s${C_RESET}\n" "$1"; }
error() { printf "${C_RED}✗ %s${C_RESET}\n" "$1"; }

prompt_yes_no() {
    local prompt_text="$1"; local choice
    while true; do read -p "$prompt_text (1 - да, 2 - нет): " choice; case $choice in 1) return 0 ;; 2) return 1 ;; *) warning "Некорректный ввод." ;; esac; done
}
wait_for_adh_service() {
    for i in {1..15}; do if systemctl is-active --quiet "$ADH_SERVICE_NAME"; then sleep 0.5; return 0; fi; sleep 1; done
    error "Служба AdGuard Home не запустилась за 15 секунд."; return 1
}
is_adh_installed() { [ -f "$ADH_CONFIG_FILE" ] && systemctl cat "$ADH_SERVICE_NAME" &>/dev/null; }
is_service_installed() { [ -f "$SERVICE_FILE_PATH" ]; }
is_adh_active() { is_adh_installed && systemctl is-active --quiet "$ADH_SERVICE_NAME"; }
backup_resolv_conf() { if [ ! -f "$RESOLV_BACKUP_PATH" ]; then cp -p "$RESOLV_CONF_PATH" "$RESOLV_BACKUP_PATH"; fi; }
restore_resolv_conf() { if [ -f "$RESOLV_BACKUP_PATH" ]; then chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; cp -p "$RESOLV_BACKUP_PATH" "$RESOLV_CONF_PATH"; rm -f "$RESOLV_BACKUP_PATH"; fi; }

install_yq() {
    if [ ! -f "/usr/local/bin/yq" ]; then
        case "$(uname -m)" in x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; armv7l) ARCH="arm" ;; *) error "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;; esac
        wget "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq && success "yq успешно установлен!"
    fi
}

# --- Определяет лучший IP-адрес для отображения в меню ---
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

# --- Проверяет систему, права доступа и устанавливает зависимости ---
initial_checks() {
    if [ "$EUID" -ne 0 ]; then error "Скрипт должен быть запущен с правами суперпользователя (через sudo)."; exit 1; fi
    
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
                error "Неподдерживаемая операционная система: $ID"; exit 1 ;;
        esac
    else 
        error "Не удалось определить операционную систему."; exit 1
    fi
    
    local dependencies=("curl" "systemctl" "chattr" "logname" "tee" "grep" "awk" "sed" "hostname" "yq" "lsof" "git" "htpasswd")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            if [ -n "$PKG_UPDATER" ]; then $PKG_UPDATER &>/dev/null; fi
            case "$cmd" in
                yq) warning "yq не найден. Устанавливаем..."; install_yq ;;
                git) warning "git не найден. Устанавливаем..."; $PKG_INSTALLER git &>/dev/null; success "'git' успешно установлен!" ;;
                htpasswd) warning "htpasswd не найден. Устанавливаем..."; $PKG_INSTALLER "$HTPASSWD_PACKAGE" &>/dev/null; success "'htpasswd' успешно установлен!" ;;
                *) error "Необходимая утилита '$cmd' не найдена."; exit 1 ;;
            esac
        fi
    done

    if ! command -v dig &>/dev/null; then 
        warning "Для расширенной проверки DNS требуется 'dig'. Устанавливаем..."
        if [ -n "$PKG_UPDATER" ]; then $PKG_UPDATER &>/dev/null; fi
        $PKG_INSTALLER $DNS_PACKAGE &>/dev/null
        success "'dig' успешно установлен!"
    fi
}

# --- Скачивает все файлы конфигураций, если они отсутствуют локально ---
download_all_configs_if_missing() {
    mkdir -p "$ADH_CONFIG_DIR"; info "Проверка и загрузка локальных файлов конфигураций..."
    declare -A configs=( ["$LOCAL_CONFIG_RU_CLASSIC_ADS"]="$CONFIG_URL_RU_CLASSIC_ADS" ["$LOCAL_CONFIG_RU_CLASSIC_NO_ADS"]="$CONFIG_URL_RU_CLASSIC_NO_ADS" ["$LOCAL_CONFIG_RU_PROXY_ADS"]="$CONFIG_URL_RU_PROXY_ADS" ["$LOCAL_CONFIG_RU_PROXY_NO_ADS"]="$CONFIG_URL_RU_PROXY_NO_ADS" ["$LOCAL_CONFIG_EN_ADS"]="$CONFIG_URL_EN_ADS" ["$LOCAL_CONFIG_EN_NO_ADS"]="$CONFIG_URL_EN_NO_ADS" )
    local all_files_exist=true
    for local_path in "${!configs[@]}"; do if [ ! -f "$local_path" ]; then all_files_exist=false; if ! curl -s -S -L -o "$local_path" "${configs[$local_path]}"; then error "Не удалось загрузить ${configs[$local_path]}"; fi; fi; done
    if [ "$all_files_exist" = true ]; then success "Все файлы конфигураций на месте."; else success "Загрузка недостающих файлов завершена."; fi
}

# --- Обновляет выбранную конфигурацию и применяет ее ---
update_and_apply_config() {
    local remote_url="$1"; local local_path="$2"
    if ! curl -s -S -L -o "$local_path" "$remote_url"; then warning "Не удалось обновить '${basename "$local_path"}'. Будет использована существующая локальная копия."; fi
    if [ -f "$local_path" ]; then cp "$local_path" "$ADH_CONFIG_FILE"; else error "Критическая ошибка: файл конфигурации отсутствует и не может быть скачан."; return 1; fi
}

# --- Создает скрипт и службу для интеграции с системой ---
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

# --- Проверяет и устраняет конфликт порта 53 со службой systemd-resolved ---
check_and_fix_port_53() {
    if lsof -i :53 | grep -q 'systemd-r'; then
        warning "Обнаружен конфликт: порт 53 занят системной службой systemd-resolved."
        if prompt_yes_no "Хотите, чтобы скрипт автоматически освободил этот порт?"; then
            info "Применяется исправление для systemd-resolved..."; mkdir -p /etc/systemd/resolved.conf.d
            cat > /etc/systemd/resolved.conf.d/adguardhome.conf <<EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
            if [ -f /etc/resolv.conf ]; then mv /etc/resolv.conf /etc/resolv.conf.backup; fi; ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf; systemctl reload-or-restart systemd-resolved
            if lsof -i :53 | grep -q 'systemd-r'; then error "Не удалось освободить порт 53. Пожалуйста, исправьте проблему вручную."; return 1; else success "Конфликт с systemd-resolved успешно устранен."; return 0; fi
        else error "Установка невозможна без освобождения порта 53."; return 1; fi
    fi; return 0
}

# --- Сохраняет и применяет учетные данные пользователя ---
save_user_credentials() {
    if [ ! -f "$ADH_CONFIG_FILE" ]; then error "Файл конфигурации не найден: $ADH_CONFIG_FILE"; return 1; fi
    USER_NAME=$(yq eval '.users[0].name' "$ADH_CONFIG_FILE"); USER_PASS_HASH=$(yq eval '.users[0].password' "$ADH_CONFIG_FILE"); HTTP_ADDRESS=$(yq eval '.http.address' "$ADH_CONFIG_FILE"); DNS_BIND_HOST=$(yq eval '.dns.bind_hosts[0] // "0.0.0.0"' "$ADH_CONFIG_FILE"); DNS_PORT=$(yq eval '.dns.port // 53' "$ADH_CONFIG_FILE")
    if [ "$USER_NAME" = "null" ] || [ -z "$USER_NAME" ] || [ "$USER_PASS_HASH" = "null" ] || [ -z "$USER_PASS_HASH" ]; then
        info "Учетные данные не найдены. Необходимо создать нового пользователя."; local NEW_USER_NAME=""; local NEW_USER_PASS=""
        while [ -z "$NEW_USER_NAME" ]; do read -p "Пожалуйста, введите новый логин: " NEW_USER_NAME; done
        while [ -z "$NEW_USER_PASS" ]; do read -s -p "Пожалуйста, введите новый пароль: " NEW_USER_PASS; printf "\n"; done
        USER_NAME="$NEW_USER_NAME"; unset USER_PASS_HASH; USER_PASS_PLAIN="$NEW_USER_PASS"; success "Новые учетные данные приняты."
    fi
}
apply_user_credentials() {
    local target_file="$1"; if [ ! -f "$target_file" ]; then return 1; fi; local password_value; if [ -n "$USER_PASS_HASH" ]; then password_value="$USER_PASS_HASH"; elif [ -n "$USER_PASS_PLAIN" ]; then password_value="$USER_PASS_PLAIN"; else error "Не удалось определить пароль для применения."; return 1; fi
    yq eval ".users[0].name = \"$USER_NAME\"" -i "$target_file"; yq eval ".users[0].password = \"$password_value\"" -i "$target_file"; yq eval ".http.address = \"$HTTP_ADDRESS\"" -i "$target_file"; yq eval ".dns.bind_hosts[0] = \"$DNS_BIND_HOST\"" -i "$target_file"; yq eval ".dns.port = $DNS_PORT" -i "$target_file"
    if [ "$(yq eval '.users | length' "$target_file")" == "0" ]; then yq eval '.users = [{"name": "'"$USER_NAME"'", "password": "'"$password_value"'"}]' -i "$target_file"; fi
}

# --- Создает резервную копию текущей конфигурации пользователя ---
create_user_backup() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return; fi
    if [ -f "$LOCAL_CONFIG_USER" ]; then if ! prompt_yes_no "Пользовательский бэкап уже существует. Перезаписать его?"; then info "Операция отменена."; return; fi; fi
    cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_USER"; success "Текущая конфигурация успешно сохранена в ${LOCAL_CONFIG_USER}"
}
force_session_ttl() { yq eval '.http.session_ttl = "876000h"' -i "$1"; }
force_cleanup_remnants() { systemctl stop "$ADH_SERVICE_NAME" &>/dev/null || true; systemctl disable "$ADH_SERVICE_NAME" &>/dev/null || true; rm -f "/etc/systemd/system/${ADH_SERVICE_NAME}" "/lib/systemd/system/${ADH_SERVICE_NAME}"; rm -rf "$ADH_DIR"; systemctl daemon-reload; }


# --- Устанавливает AdGuard Home и выполняет первоначальную настройку ---
install_adh() {
    if is_adh_installed; then warning "AdGuard Home уже установлен."; return; fi
    local service_file_exists=false; systemctl cat "$ADH_SERVICE_NAME" &>/dev/null && service_file_exists=true
    if [ -d "$ADH_DIR" ] || [ "$service_file_exists" = true ]; then error "Обнаружены остатки от предыдущей установки."; if prompt_yes_no "Удалить их для продолжения?"; then force_cleanup_remnants; else error "Установка невозможна."; return 1; fi; fi
    if ! check_and_fix_port_53; then return 1; fi
    
    backup_resolv_conf; local INSTALL_LOG; INSTALL_LOG=$(mktemp); info "Установка началась, подождите..."
    if ! curl -s -S -L "$ADH_INSTALL_SCRIPT_URL" | sh -s -- -v > "$INSTALL_LOG" 2>&1; then
        if grep -q "existing AdGuard Home installation is detected" "$INSTALL_LOG"; then
            warning "Официальный установщик обнаружил остатки. Запускаю принудительную очистку..."; uninstall_adh --force
            info "Очистка завершена. Повторная попытка установки...";
            if ! curl -s -S -L "$ADH_INSTALL_SCRIPT_URL" | sh -s -- -v > "$INSTALL_LOG" 2>&1; then error "Повторная установка AdGuard Home также не удалась:"; cat "$INSTALL_LOG"; rm -f "$INSTALL_LOG"; exit 1; fi
        else error "Установка AdGuard Home не удалась:"; cat "$INSTALL_LOG"; rm -f "$INSTALL_LOG"; exit 1; fi
    fi
    rm -f "$INSTALL_LOG"; systemctl daemon-reload; success "Установка AdGuard Home успешно завершена!"
    
    local server_ip; server_ip=$(hostname -I | awk '{print $1}'); printf "\n1. Перейдите по ссылке в браузер и завершите ручную настройку:\n"; if [ -n "$server_ip" ]; then echo -e "🔗 ${C_YELLOW}http://${server_ip}:3000${C_RESET}"; fi
    local choice; while true; do read -p "2. Когда закончите настройку введите '1' для продолжения: " choice; if [[ "$choice" == "1" ]]; then if [ -f "$ADH_CONFIG_FILE" ]; then break; else warning "Файл конфигурации все еще не создан. Завершите все шаги в веб-интерфейсе."; fi; else warning "Пожалуйста, завершите настройку и введите '1'."; fi; done
    
    download_all_configs_if_missing
    
    printf "\n"; info "Сохранение стандартной конфигурации..."; mkdir -p "$ADH_CONFIG_DIR"; cp "$ADH_CONFIG_FILE" "$ADH_CONFIG_BACKUP"; cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_STD"; success "Стандартная конфигурация сохранена!"
    save_user_credentials
    
    printf "\n"
    if prompt_yes_no "Заменить стандартную конфигурацию на заранее подготовленную?"; then
        printf "\n"; local cfg_choice; while true; do printf "Выберите конфигурацию:\n1. Для российского сервера\n2. Для зарубежного сервера\n"; read -p "Ваш выбор [1-2]: " cfg_choice; if [[ "$cfg_choice" == "1" || "$cfg_choice" == "2" ]]; then break; else warning "Некорректный ввод."; fi; done
        local remote_url; local local_path
        if [ "$cfg_choice" -eq 1 ]; then
            local use_proxy=false; if prompt_yes_no "Использовать прокси DNS для обхода геоблокировки?"; then use_proxy=true; fi
            local use_ad_blocking=false; if prompt_yes_no "Включить блокировку рекламы?"; then use_ad_blocking=true; fi
            if [ "$use_proxy" = true ]; then
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_PROXY_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_ADS"; else remote_url="$CONFIG_URL_RU_PROXY_NO_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_NO_ADS"; fi
            else
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_CLASSIC_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_ADS"; else remote_url="$CONFIG_URL_RU_CLASSIC_NO_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_NO_ADS"; fi
            fi
        else
            if prompt_yes_no "Включить блокировку рекламы?"; then remote_url="$CONFIG_URL_EN_ADS"; local_path="$LOCAL_CONFIG_EN_ADS"; else remote_url="$CONFIG_URL_EN_NO_ADS"; local_path="$LOCAL_CONFIG_EN_NO_ADS"; fi
        fi
        printf "\n"; info "Применение выбранной конфигурации..."; update_and_apply_config "$remote_url" "$local_path"; apply_user_credentials "$ADH_CONFIG_FILE"
    fi

    force_session_ttl "$ADH_CONFIG_FILE"; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service; create_integration_services
    
    set +e; test_adh --silent; local test_result=$?; true; set -e
    if [ $test_result -eq 0 ]; then success "AdGuard Home успешно работает!";
    elif [ $test_result -eq 9 ]; then
        warning "Первичный тест DNS не удался (код 9). Попытка перезапуска службы..."; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service; sleep 2
        set +e; test_adh --silent; test_result=$?; true; set -e
        if [ $test_result -ne 0 ]; then error "Повторный тест DNS после перезапуска также не удался. Проверьте конфигурацию вручную."; else success "AdGuard Home успешно работает после перезапуска!"; fi
    else error "Не удалось выполнить DNS-запрос через AdGuard Home (код: $test_result)."; fi
}

# --- Позволяет пользователю сменить текущую конфигурацию AdGuard Home ---
change_config() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return 1; fi
    
    local menu_prompt
    menu_prompt="Выберите конфигурацию для применения:"
    menu_prompt+="\n1. Для российского сервера"
    menu_prompt+="\n2. Для зарубежного сервера"
    menu_prompt+="\n3. Стандартная (созданная при установке)"
    menu_prompt+="\n4. Восстановить из пользовательской резервной копии"
    menu_prompt+="\n5. Вернуться в главное меню\n"

    local menu_choice
    while true; do 
        printf "%b" "$menu_prompt"
        read -p "Ваш выбор [1-5]: " menu_choice
        if [[ "$menu_choice" =~ ^[1-5]$ ]]; then 
            if [[ "$menu_choice" -eq 5 ]]; then 
                info "Возврат в главное меню..."
                return 100
            fi
            break
        else 
            warning "Некорректный ввод."
        fi
    done

    # Сохраняем текущие данные ПЕРЕД любыми изменениями
    save_user_credentials
    local should_apply_credentials=false

    case $menu_choice in
        1) 
            local use_proxy=false; if prompt_yes_no "Использовать прокси DNS для обхода геоблокировки?"; then use_proxy=true; fi
            local use_ad_blocking=false; if prompt_yes_no "Включить блокировку рекламы?"; then use_ad_blocking=true; fi
            if [ "$use_proxy" = true ]; then
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_PROXY_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_ADS"; else remote_url="$CONFIG_URL_RU_PROXY_NO_ADS"; local_path="$LOCAL_CONFIG_RU_PROXY_NO_ADS"; fi
            else
                if [ "$use_ad_blocking" = true ]; then remote_url="$CONFIG_URL_RU_CLASSIC_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_ADS"; else remote_url="$CONFIG_URL_RU_CLASSIC_NO_ADS"; local_path="$LOCAL_CONFIG_RU_CLASSIC_NO_ADS"; fi
            fi
            info "Применение конфигурации для российского сервера..."; update_and_apply_config "$remote_url" "$local_path"
            should_apply_credentials=true 
            ;;
        2) 
            if prompt_yes_no "Включить блокировку рекламы?"; then remote_url="$CONFIG_URL_EN_ADS"; local_path="$LOCAL_CONFIG_EN_ADS"; else remote_url="$CONFIG_URL_EN_NO_ADS"; local_path="$LOCAL_CONFIG_EN_NO_ADS"; fi
            info "Применение конфигурации для зарубежного сервера..."; update_and_apply_config "$remote_url" "$local_path"
            should_apply_credentials=true 
            ;;
        3) 
            if [ -f "$LOCAL_CONFIG_STD" ]; then 
                cp "$LOCAL_CONFIG_STD" "$ADH_CONFIG_FILE"
                success "Стандартная конфигурация восстановлена."
                should_apply_credentials=true
            else 
                error "Файл стандартной конфигурации не найден."
                return 1
            fi 
            ;;
        4) 
            if [ -f "$LOCAL_CONFIG_USER" ]; then 
                cp "$LOCAL_CONFIG_USER" "$ADH_CONFIG_FILE"
                success "Конфигурация из пользовательской резервной копии восстановлена."
                should_apply_credentials=true
            else 
                error "Пользовательская резервная копия не найдена."
                return 1
            fi 
            ;;
    esac

    # Эта логика теперь работает для ВСЕХ вариантов (1, 2, 3 и 4)
    if [ "$should_apply_credentials" = true ]; then 
        apply_user_credentials "$ADH_CONFIG_FILE"
    fi

    force_session_ttl "$ADH_CONFIG_FILE"
    systemctl restart "$ADH_SERVICE_NAME"
    wait_for_adh_service
    success "Конфигурация успешно применена. Проверьте работу AdGuard Home."
}

# --- Позволяет пользователю изменить адрес веб-панели или DNS-службы ---
change_address_menu() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return 1; fi
    local menu_choice; while true; do printf "Какой адрес вы хотите изменить?\n1. Адрес веб-панели\n2. Адрес DNS-службы\n3. Вернуться в главное меню\n"; read -p "Ваш выбор [1-3]: " menu_choice; if [[ "$menu_choice" =~ ^[1-3]$ ]]; then break; else warning "Некорректный ввод."; fi; done
    if [[ "$menu_choice" -eq 3 ]]; then return 100; fi

    mapfile -t available_ips < <(ip -4 -o addr show | awk '{print $4}' | cut -d'/' -f1)
    local choices=("0.0.0.0 (на всех интерфейсах)")
    for ip in "${available_ips[@]}"; do choices+=("$ip"); done
    
    # ИЗМЕНЕНО: Полностью ручная отрисовка меню для точного форматирования
    printf "\nВыберите IP-адрес из списка:\n\n"
    
    local i=1
    for item in "${choices[@]}"; do
        printf "%s) %s\n" "$i" "$item"
        ((i++))
    done
    
    printf "\n" # Пустая строка перед приглашением к вводу

    local num_choices=${#choices[@]}
    local ip_choice
    local selected_ip
    
    # Цикл для получения и валидации ввода
    while true; do
        read -p "Ваш выбор [1-${num_choices}]: " ip_choice
        if [[ "$ip_choice" =~ ^[0-9]+$ ]] && [ "$ip_choice" -ge 1 ] && [ "$ip_choice" -le "$num_choices" ]; then
            selected_ip=${choices[$((ip_choice - 1))]}
            selected_ip=$(echo "$selected_ip" | awk '{print $1}')
            break
        else
            warning "Некорректный ввод."
        fi
    done
    
    if [ "$menu_choice" -eq 1 ]; then
        local port; while true; do
            printf "\n"
            read -p "Введите новый порт для веб-панели (например, 8080): " port
            if ! [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
                warning "Пожалуйста, введите корректный номер порта (1-65535)."
                continue
            fi
            
            local pid
            pid=$(lsof -t -i :"$port" 2>/dev/null | head -n 1)

            if [ -n "$pid" ]; then
                local process_name
                process_name=$(ps -p "$pid" -o comm=)
                
                if [[ "$process_name" != "AdGuardHome" ]]; then
                    error "Порт $port уже занят процессом '${process_name}'. Пожалуйста, выберите другой."
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
    info "Перезапуск AdGuard Home для применения изменений..."; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service
    success "Адрес успешно изменен!"
}

# --- Позволяет пользователю изменить логин и пароль ---
change_credentials() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return 1; fi

    # Запрос на подтверждение перед началом
    if ! prompt_yes_no "Продолжить изменение логина и пароля?"; then
        info "Операция отменена."
        return 100 # Возвращаем специальный код для выхода в меню без "Нажмите Enter"
    fi
    printf "\n" # Пустая строка для форматирования

    local new_user; local new_pass
    local valid_chars='^[A-Za-z0-9_.-]+$'

    while true; do
        read -p "Введите новый логин: " new_user
        if [[ "$new_user" =~ $valid_chars ]]; then break; else error "Логин может содержать только латинские буквы, цифры, точки, дефисы и подчеркивания."; fi
    done
    
    if prompt_yes_no "Сгенерировать случайный и надежный пароль?"; then
        new_pass=$(tr -dc 'A-Za-z0-9_!@#$%^&*' < /dev/urandom | head -c 64)
        printf "\n"
        printf "Сохраните новый пароль: ${C_YELLOW}%s${C_RESET}\n" "$new_pass"
        printf "\n"
    fi
    
    # Этот блок выполнится, только если пользователь отказался от генерации пароля
    while [ -z "$new_pass" ]; do
        read -s -p "Введите новый пароль (минимум 6 символов): " new_pass; printf "\n"
        if [[ ! "$new_pass" =~ ^[A-Za-z0-9\_\.\!\@\#\$\%\^\&\*\(\)\+\=\-]+$ ]]; then
            error "Пароль может содержать только латинские буквы, цифры и символы: _ . ! @ # $ % ^ & * ( ) + = -"
            new_pass=""
        elif [ ${#new_pass} -lt 6 ]; then
            error "Пароль должен содержать минимум 6 символов."
            new_pass=""
        fi
    done
    
    info "Изменение учетных данных..."
    
    local NEW_PASS_HASH
    NEW_PASS_HASH=$(htpasswd -nbB -C 10 "tempuser" "$new_pass" | cut -d':' -f2)

    if [[ -z "$NEW_PASS_HASH" ]]; then
        error "Не удалось сгенерировать хэш пароля. Обновление отменено."
        return 1
    fi

    systemctl stop "$ADH_SERVICE_NAME"

    yq eval ".users[0].name = \"$new_user\"" -i "$ADH_CONFIG_FILE"
    yq eval ".users[0].password = \"$NEW_PASS_HASH\"" -i "$ADH_CONFIG_FILE"
    
    info "Запуск AdGuard Home..."; systemctl start "$ADH_SERVICE_NAME"; wait_for_adh_service
    success "Учетные данные успешно изменены."
}

# --- Тестирует работоспособность AdGuard Home ---
test_adh() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return 1; fi
    if [ "$1" == "--silent" ]; then set +e; dig @127.0.0.1 +time=2 +tries=2 +short ya.ru >/dev/null; local test_result=$?; true; set -e; return $test_result; fi
    set +e; info "Проверка работы AdGuard Home..."; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; local all_tests_ok=true
    if dig @127.0.0.1 +time=2 +tries=2 ya.ru A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "1. ${C_GREEN}Успешно${C_RESET} получен IP (ya.ru)\n"; else printf "1. ${C_RED}Ошибка${C_RESET} при получении IP (ya.ru)\n"; all_tests_ok=false; fi
    if dig @127.0.0.1 +time=2 +tries=2 google.com A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "2. ${C_GREEN}Успешно${C_RESET} получен IP (google.com)\n"; else printf "2. ${C_RED}Ошибка${C_RESET} при получении IP (google.com)\n"; all_tests_ok=false; fi
    local ad_result; ad_result=$(dig @127.0.0.1 +time=2 +tries=2 doubleclick.net A +short); if [[ "$ad_result" == "0.0.0.0" || -z "$ad_result" ]]; then printf "3. ${C_GREEN}Успешно${C_RESET} заблокирован (doubleclick.net)\n"; else printf "3. ${C_RED}Ошибка${C_RESET} блокировки (doubleclick.net)\n"; all_tests_ok=false; fi
    local test_ok=false; local dnssec_valid_domains=("www.internic.net" "www.dnssec-tools.org" "www.verisign.com" "www.nlnetlabs.nl"); for domain in "${dnssec_valid_domains[@]}"; do if dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec | grep -q "flags:.* ad;"; then printf "4. ${C_GREEN}Успешно${C_RESET} пройден DNSSEC (валидная подпись на %s)\n" "$domain"; test_ok=true; break; fi; done; if ! $test_ok; then printf "4. ${C_RED}Ошибка${C_RESET} DNSSEC (валидная подпись)\n"; all_tests_ok=false; fi
    test_ok=false; local dnssec_invalid_domains=("dnssec-failed.org" "www.dnssec-failed.org" "brokendnssec.net" "dlv.isc.org"); for domain in "${dnssec_invalid_domains[@]}"; do local dnssec_fail_output; dnssec_fail_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec); if [[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: SERVFAIL"* ]] || ([[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* ]] && [[ "$dnssec_fail_output" != *"flags:.* ad;"* ]]); then printf "5. ${C_GREEN}Успешно${C_RESET} пройден DNSSEC (невалидная подпись на %s)\n" "$domain"; test_ok=true; break; fi; done; if ! $test_ok; then printf "5. ${C_RED}Ошибка${C_RESET} DNSSEC (невалидная подпись)\n"; all_tests_ok=false; fi
    test_ok=false; local dnssec_insecure_domains=("example.com" "github.com" "iana.org" "icann.org"); for domain in "${dnssec_insecure_domains[@]}"; do local dnssec_insecure_output; dnssec_insecure_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec); if [[ "$dnssec_insecure_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* && "$dnssec_insecure_output" != *"flags:.* ad;"* ]]; then printf "6. ${C_GREEN}Успешно${C_RESET} пройден DNSSEC (отсутствующая подпись на %s)\n" "$domain"; test_ok=true; break; fi; done; if ! $test_ok; then printf "6. ${C_RED}Ошибка${C_RESET} DNSSEC (отсутствующая подпись)\n"; all_tests_ok=false; fi
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; set -e; return 0
}

# --- Полностью удаляет AdGuard Home и все связанные с ним файлы ---
uninstall_adh() {
    if ! is_adh_installed && [ ! -d "$ADH_DIR" ]; then warning "AdGuard Home не установлен."; return; fi
    local force_uninstall=false; if [ "$1" == "--force" ]; then force_uninstall=true; fi
    if ! $force_uninstall && ! prompt_yes_no "Вы уверены, что хотите полностью удалить AdGuard Home?"; then info "Удаление отменено."; return 1; fi
    info "Удаление началось, подождите..."; chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    if is_service_installed; then systemctl disable --now set-dns.service 2>/dev/null || true; rm -f "$SERVICE_FILE_PATH" "$OVERWRITE_DNS_SCRIPT_PATH"; fi
    if [ -x "$ADH_DIR/AdGuardHome" ]; then "$ADH_DIR/AdGuardHome" -s uninstall &>/dev/null; fi
    force_cleanup_remnants; restore_resolv_conf; chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; success "AdGuard Home полностью удален!"
}

# --- Переустанавливает AdGuard Home ---
reinstall_adh() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return; fi
    if ! prompt_yes_no "Вы уверены, что хотите ПЕРЕУСТАНОВИТЬ AdGuard Home?"; then info "Переустановка отменена."; return 1; fi
    printf "\n"; uninstall_adh --force; printf "\n"; install_adh
}

# --- Управляет службой AdGuard Home ---
manage_service() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return; fi
    set +e; systemctl "$1" "$ADH_SERVICE_NAME"; true; set -e
}

# --- Отображает главное меню и обрабатывает выбор пользователя ---
main_menu() {
    while true; do
        clear;
        printf "${C_GREEN}AdGuard Home Easy Setup by Internet Helper${C_RESET}\n"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if is_adh_installed; then
           local web_address; web_address=$(yq eval '.http.address' "$ADH_CONFIG_FILE" 2>/dev/null)
           local ip_part; ip_part=$(echo "$web_address" | cut -d':' -f1); local port_part; port_part=$(echo "$web_address" | cut -d':' -f2)
           local display_url
           if [[ "$ip_part" == "0.0.0.0" ]]; then local display_ip; display_ip=$(get_display_ip); display_url="http://${display_ip}:${port_part}"; else display_url="http://${web_address}"; fi
           if is_adh_active; then printf "⚙️  Работает:\n${C_GREEN}🟢 %s${C_RESET}\n" "$display_url"; else printf "⚙️  Остановлен:\n${C_YELLOW}🟡 %s${C_RESET}\n" "$display_url"; fi
        else
           printf "${C_RED}🔴 Не установлен${C_RESET}\n"
        fi
        
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if is_adh_installed; then
            printf "1. Запустить AdGuard Home\n2. Остановить AdGuard Home\n3. Перезапустить AdGuard Home\n"
            printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            printf "4. Изменить конфигурацию\n5. Изменить адрес\n6. Изменить логин и пароль\n"
            printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            printf "7. Сделать резервную копию\n8. Протестировать работу\n"
            printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            printf "9. Переустановить\n10. Удалить\n"
        else
            printf "1. Установить AdGuard Home\n"
        fi
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; echo "0. Выйти"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        local menu_choice; read -p "Выберите действие: " menu_choice; printf "\n"
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
        if [[ "$action_to_run" != *"manage_service"* && "$return_code" -ne 100 ]]; then printf "\n"; read -p "Нажмите Enter для продолжения..."; fi
    done
}

# --- ТОЧКА ВХОДА В СКРИПТ ---
initial_checks
main_menu