#!/bin/bash

# AdGuard Home Easy Setup by Internet Helper v1.0 (Start)

# Выход из скрипта при любой ошибке, включая ошибки в конвейерах (pipes)
set -e
set -o pipefail

# --- ПЕРЕМЕННЫЕ И КОНСТАНТЫ ---
# Цвета для вывода
C_RESET='\033[0m';
C_RED='\033[0;31m';
C_GREEN='\033[38;2;0;210;106m';
C_YELLOW='\033[0;33m';
C_BLUE='\033[0;34m';
C_CYAN='\033[0;36m'

# Пути к файлам и URL
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
CONFIG_URL_RU="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/AdGuardHome.yaml"
CONFIG_URL_EN="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/english/AdGuardHome.yaml"
CONFIG_URL_RU_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/russian/ad-filters-off/AdGuardHome.yaml"
CONFIG_URL_EN_NO_ADS="https://raw.githubusercontent.com/Internet-Helper/AdGuard-Home/main/files/linux/english/ad-filters-off/AdGuardHome.yaml"


# --- ФУНКЦИИ-ПЕРЕХВАТЧИКИ И ОЧИСТКИ ---
# Перехватывает завершение скрипта, при ошибке выполняет откат изменений.
handle_exit() {
    local EXIT_CODE=$?
    chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 130 ] && [ $EXIT_CODE -ne 100 ]; then
        printf "\n${C_RED}ОШИБКА: Скрипт завершился с кодом %s.${C_RESET}\n" "$EXIT_CODE"
        printf "${C_YELLOW}Выполняется откат изменений...${C_RESET}\n"; restore_resolv_conf; printf "${C_GREEN}Откат завершен.${C_RESET}\n"
    fi
}

# Перехватывает прерывание скрипта (Ctrl+C), выполняет откат изменений.
handle_interrupt() {
    printf "\n\n${C_YELLOW}Скрипт прерван. Выполняется откат изменений...${C_RESET}\n"
    restore_resolv_conf
    printf "${C_GREEN}Откат завершен.${C_RESET}\n"
    exit 130
}

trap 'handle_exit' EXIT
trap 'handle_interrupt' SIGINT SIGTERM SIGHUP

# --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---
# Выводит информационное сообщение синим цветом.
info() { printf "${C_BLUE}> %s${C_RESET}\n" "$1"; }
# Выводит сообщение об успехе зеленым цветом.
success() { printf "${C_GREEN}✓ %s${C_RESET}\n" "$1"; }
# Выводит предупреждение желтым цветом.
warning() { printf "${C_YELLOW}! %s${C_RESET}\n" "$1"; }
# Выводит сообщение об ошибке красным цветом.
error() { printf "${C_RED}✗ %s${C_RESET}\n" "$1"; }

# Запрашивает у пользователя ответ "да" или "нет".
prompt_yes_no() {
    local prompt_text="$1"
    while true; do read -p "$prompt_text (1 - да, 2 - нет): " choice; case $choice in 1) return 0 ;; 2) return 1 ;; *) warning "Некорректный ввод." ;; esac; done
}

# Скачивает файл конфигурации, при неудаче использует локальную копию.
get_config() {
    local remote_url="$1"; local local_path="$2"
    if curl -s -S -L -o "$ADH_CONFIG_FILE" "$remote_url"; then
        cp "$ADH_CONFIG_FILE" "$local_path"
    else
        warning "Не удалось скачать свежую конфигурацию. Используется локальная копия."
        if [ -f "$local_path" ]; then cp "$local_path" "$ADH_CONFIG_FILE"; else error "Локальная копия не найдена!"; return 1; fi
    fi
}

# Ожидает запуска службы AdGuard Home в течение 15 секунд.
wait_for_adh_service() {
    for i in {1..15}; do if systemctl is-active --quiet "$ADH_SERVICE_NAME"; then sleep 0.5; return 0; fi; sleep 1; done
    error "Служба AdGuard Home не запустилась за 15 секунд."; return 1
}

# Проверяет, установлен ли AdGuard Home.
is_adh_installed() { [ -f "$ADH_CONFIG_FILE" ] && systemctl cat "$ADH_SERVICE_NAME" &>/dev/null; }
# Проверяет, установлена ли служба интеграции `set-dns.service`.
is_service_installed() { [ -f "$SERVICE_FILE_PATH" ]; }
# Проверяет, активна ли служба AdGuard Home в данный момент.
is_adh_active() { is_adh_installed && systemctl is-active --quiet "$ADH_SERVICE_NAME"; }

# Создает резервную копию файла /etc/resolv.conf.
backup_resolv_conf() { if [ ! -f "$RESOLV_BACKUP_PATH" ]; then cp -p "$RESOLV_CONF_PATH" "$RESOLV_BACKUP_PATH"; fi; }
# Восстанавливает файл /etc/resolv.conf из резервной копии.
restore_resolv_conf() { if [ -f "$RESOLV_BACKUP_PATH" ]; then chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; cp -p "$RESOLV_BACKUP_PATH" "$RESOLV_CONF_PATH"; rm -f "$RESOLV_BACKUP_PATH"; fi; }

# Выполняет первоначальные проверки системы (права, зависимости, ОС).
initial_checks() {
    if [ "$EUID" -ne 0 ]; then error "Скрипт должен быть запущен с правами суперпользователя (через sudo)."; exit 1; fi
    local dependencies=("curl" "systemctl" "chattr" "logname" "tee" "grep" "awk" "sed" "hostname" "yq" "lsof"); for cmd in "${dependencies[@]}"; do if ! command -v "$cmd" &>/dev/null; then if [ "$cmd" = "yq" ]; then warning "yq не найден. Устанавливаем..."; install_yq; else error "Необходимая утилита '$cmd' не найдена."; exit 1; fi; fi; done
    if [ -f /etc/os-release ]; then . /etc/os-release; case "$ID" in debian|ubuntu) PKG_UPDATER="apt-get update -y"; PKG_INSTALLER="apt-get install -y"; DNS_PACKAGE="dnsutils" ;; centos|almalinux|rocky|fedora) PKG_UPDATER=""; if [ "$ID" = "fedora" ]; then PKG_INSTALLER="dnf install -y"; else PKG_INSTALLER="yum install -y"; fi; DNS_PACKAGE="bind-utils" ;; *) error "Неподдерживаемая операционная система: $ID"; exit 1 ;; esac; else error "Не удалось определить операционную систему."; exit 1; fi
    if ! command -v dig &>/dev/null; then
        warning "Для расширенной проверки DNS требуется 'dig'. Устанавливаем..."
        if [ -n "$PKG_UPDATER" ]; then $PKG_UPDATER &>/dev/null; fi
        $PKG_INSTALLER $DNS_PACKAGE &>/dev/null
        success "'dig' успешно установлен!"
    fi
}

# Устанавливает утилиту yq, если она отсутствует.
install_yq() {
    if [ ! -f "/usr/local/bin/yq" ]; then
        case "$(uname -m)" in
            x86_64) ARCH="amd64" ;;
            aarch64) ARCH="arm64" ;;
            armv7l) ARCH="arm" ;;
            *) error "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
        esac
        wget "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -O /usr/local/bin/yq && \
        chmod +x /usr/local/bin/yq && \
        success "yq успешно установлен!"
    fi
}

# Создает скрипт и службу systemd для автоматической настройки DNS на 127.0.0.1.
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

# Проверяет, занят ли порт 53 службой systemd-resolved, и предлагает исправить конфликт.
check_and_fix_port_53() {
    if lsof -i :53 | grep -q 'systemd-r'; then
        warning "Обнаружен конфликт: порт 53 занят системной службой systemd-resolved."
        if prompt_yes_no "Хотите, чтобы скрипт автоматически освободил этот порт?"; then
            info "Применяется исправление для systemd-resolved..."
            
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
                error "Не удалось освободить порт 53. Пожалуйста, исправьте проблему вручную."
                return 1
            else
                success "Конфликт с systemd-resolved успешно устранен."
                return 0
            fi
        else
            error "Установка невозможна без освобождения порта 53."
            return 1
        fi
    fi
    return 0
}

# --- ФУНКЦИИ УПРАВЛЕНИЯ КОНФИГУРАЦИЕЙ ---
# Сохраняет имя пользователя, хэш пароля и сетевые настройки из текущей конфигурации.
save_user_credentials() {
    if [ ! -f "$ADH_CONFIG_FILE" ]; then error "Файл конфигурации не найден: $ADH_CONFIG_FILE"; return 1; fi
    
    # Пытаемся прочитать существующие учетные данные
    USER_NAME=$(yq eval '.users[0].name' "$ADH_CONFIG_FILE")
    USER_PASS_HASH=$(yq eval '.users[0].password' "$ADH_CONFIG_FILE")
    HTTP_ADDRESS=$(yq eval '.http.address // "0.0.0.0:80"' "$ADH_CONFIG_FILE")
    DNS_BIND_HOST=$(yq eval '.dns.bind_hosts[0] // "0.0.0.0"' "$ADH_CONFIG_FILE")
    DNS_PORT=$(yq eval '.dns.port // 53' "$ADH_CONFIG_FILE")

    # Если учетные данные не найдены, запрашиваем у пользователя новые
    if [ "$USER_NAME" = "null" ] || [ -z "$USER_NAME" ] || [ "$USER_PASS_HASH" = "null" ] || [ -z "$USER_PASS_HASH" ]; then
        info "Учетные данные не найдены. Необходимо создать нового пользователя."
        local NEW_USER_NAME=""
        local NEW_USER_PASS=""
        while [ -z "$NEW_USER_NAME" ]; do
            read -p "Пожалуйста, введите новый логин: " NEW_USER_NAME
        done
        while [ -z "$NEW_USER_PASS" ]; do
            read -s -p "Пожалуйста, введите новый пароль: " NEW_USER_PASS
            printf "\n"
        done
        
        USER_NAME="$NEW_USER_NAME"
        unset USER_PASS_HASH
        USER_PASS_PLAIN="$NEW_USER_PASS"
        success "Новые учетные данные приняты."
    fi
}

# Применяет сохраненные учетные данные и сетевые настройки к новому файлу конфигурации.
apply_user_credentials() {
    local target_file="$1"; if [ ! -f "$target_file" ]; then return 1; fi

    local password_value
    if [ -n "$USER_PASS_HASH" ]; then
        password_value="$USER_PASS_HASH"
    elif [ -n "$USER_PASS_PLAIN" ]; then
        password_value="$USER_PASS_PLAIN"
    else
        error "Не удалось определить пароль для применения."
        return 1
    fi

    # Применяем все настройки
    yq eval ".users[0].name = \"$USER_NAME\"" -i "$target_file"
    yq eval ".users[0].password = \"$password_value\"" -i "$target_file"
    yq eval ".http.address = \"$HTTP_ADDRESS\"" -i "$target_file"
    yq eval ".dns.bind_hosts[0] = \"$DNS_BIND_HOST\"" -i "$target_file"
    yq eval ".dns.port = $DNS_PORT" -i "$target_file"

    # Гарантируем, что массив users существует, если его не было в шаблоне
    if [ "$(yq eval '.users | length' "$target_file")" == "0" ]; then
         yq eval '.users = [{"name": "'"$USER_NAME"'", "password": "'"$password_value"'"}]' -i "$target_file"
    fi
}


# Создает резервную копию текущей конфигурации пользователя.
create_user_backup() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return; fi
    if [ -f "$LOCAL_CONFIG_USER" ]; then if ! prompt_yes_no "Пользовательский бэкап уже существует. Перезаписать его?"; then info "Операция отменена."; return; fi; fi
    cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_USER"; success "Текущая конфигурация успешно сохранена в ${LOCAL_CONFIG_USER}"
}

# Устанавливает очень долгое время жизни сессии в файле конфигурации.
force_session_ttl() { yq eval '.http.session_ttl = "876000h"' -i "$1"; }
# Принудительно удаляет все остатки предыдущей установки AdGuard Home.
force_cleanup_remnants() { systemctl stop "$ADH_SERVICE_NAME" &>/dev/null || true; systemctl disable "$ADH_SERVICE_NAME" &>/dev/null || true; rm -f "/etc/systemd/system/${ADH_SERVICE_NAME}" "/lib/systemd/system/${ADH_SERVICE_NAME}"; rm -rf "$ADH_DIR"; systemctl daemon-reload; }

# --- ОСНОВНЫЕ ФУНКЦИИ (ПУНКТЫ МЕНЮ) ---
# Устанавливает AdGuard Home и выполняет первоначальную настройку.
install_adh() {
    if is_adh_installed; then warning "AdGuard Home уже установлен."; return; fi
    local service_file_exists=false; systemctl cat "$ADH_SERVICE_NAME" &>/dev/null && service_file_exists=true
    if [ -d "$ADH_DIR" ] || [ "$service_file_exists" = true ]; then error "Обнаружены остатки от предыдущей установки."; if prompt_yes_no "Удалить их для продолжения?"; then force_cleanup_remnants; else error "Установка невозможна."; return 1; fi; fi
    
    if ! check_and_fix_port_53; then return 1; fi
    
    backup_resolv_conf;
    local INSTALL_LOG; INSTALL_LOG=$(mktemp); info "Установка началась, подождите..."
    if ! curl -s -S -L "$ADH_INSTALL_SCRIPT_URL" | sh -s -- -v > "$INSTALL_LOG" 2>&1; then error "Установка AdGuard Home не удалась:"; cat "$INSTALL_LOG"; rm -f "$INSTALL_LOG"; exit 1; fi
    rm -f "$INSTALL_LOG"; systemctl daemon-reload; success "Установка AdGuard Home успешно завершена!"
    
    local server_ip; server_ip=$(hostname -I | awk '{print $1}')
    printf "\n1. Перейдите по ссылке в браузер и завершите ручную настройку:\n"
    if [ -n "$server_ip" ]; then echo -e "🔗 ${C_YELLOW}http://${server_ip}:3000${C_RESET}"; fi
    
    while true; do read -p "2. Когда закончите настройку введите '1' для продолжения: " choice; if [[ "$choice" == "1" ]]; then if [ -f "$ADH_CONFIG_FILE" ]; then break; else warning "Файл конфигурации все еще не создан. Завершите все шаги в веб-интерфейсе по ссылке выше."; fi; else warning "Пожалуйста, завершите настройку и введите '1'."; fi; done
    
    printf "\n"
    info "Сохранение стандартной конфигурации..."
    mkdir -p "$ADH_BACKUP_DIR"
    cp "$ADH_CONFIG_FILE" "$ADH_CONFIG_BACKUP"
    cp "$ADH_CONFIG_FILE" "$LOCAL_CONFIG_STD"
    success "Стандартная конфигурация сохранена!"
    
    curl -s -S -L -o "$LOCAL_CONFIG_RU" "$CONFIG_URL_RU" &>/dev/null || true
    curl -s -S -L -o "$LOCAL_CONFIG_EN" "$CONFIG_URL_EN" &>/dev/null || true
    save_user_credentials
    
    printf "\n"
    if prompt_yes_no "Заменить стандартную конфигурацию на заранее подготовленную?"; then
        printf "\n"
        while true; do printf "Выберите конфигурацию:\n1. Для российского сервера\n2. Для зарубежного сервера\n"; read -p "Ваш выбор [1-2]: " cfg_choice; if [[ "$cfg_choice" == "1" || "$cfg_choice" == "2" ]]; then break; else warning "Некорректный ввод."; fi; done
        
        local use_ad_blocking
        if prompt_yes_no "Включить блокировку рекламы?"; then
            use_ad_blocking=true
        else
            use_ad_blocking=false
        fi

        local target_url; local target_local_path
        if [ "$cfg_choice" -eq 1 ]; then # Российский сервер
            target_local_path="$LOCAL_CONFIG_RU"
            if [ "$use_ad_blocking" = true ]; then target_url="$CONFIG_URL_RU"; else target_url="$CONFIG_URL_RU_NO_ADS"; fi
        else # Зарубежный сервер
            target_local_path="$LOCAL_CONFIG_EN"
            if [ "$use_ad_blocking" = true ]; then target_url="$CONFIG_URL_EN"; else target_url="$CONFIG_URL_EN_NO_ADS"; fi
        fi
        
        printf "\n"
        info "Замена началась, подождите..."
        get_config "$target_url" "$target_local_path"
        apply_user_credentials "$ADH_CONFIG_FILE"
    fi

    force_session_ttl "$ADH_CONFIG_FILE"; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service; create_integration_services
    
    set +e; test_adh --silent; local test_result=$?; true; set -e
    if [ $test_result -eq 0 ]; then success "AdGuard Home успешно работает!"; else error "Не удалось выполнить DNS-запрос через AdGuard Home."; fi
}

# Позволяет пользователю сменить текущую конфигурацию AdGuard Home.
change_config() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return 1; fi
    while true; do
        printf "Выберите конфигурацию для применения:\n1. Для российского сервера\n2. Для зарубежного сервера\n3. Стандартная (созданная при установке)\n4. Восстановить из пользовательской резервной копии\n5. Вернуться в главное меню\n"
        read -p "Ваш выбор [1-5]: " choice
        printf "\n"

        if [[ "$choice" =~ ^[1-5]$ ]]; then
            if [[ "$choice" -eq 5 ]]; then
                info "Возврат в главное меню..."
                return 100
            fi
            break
        else
            warning "Некорректный ввод."
            printf "\n"
        fi
    done
    
    save_user_credentials; info "Применение конфигурации..."
    
    local should_apply_credentials=false
    case $choice in
        1|2)
            local use_ad_blocking
            if prompt_yes_no "Включить блокировку рекламы?"; then
                use_ad_blocking=true
            else
                use_ad_blocking=false
            fi

            local target_url; local target_local_path
            if [ "$choice" -eq 1 ]; then # Российский сервер
                target_local_path="$LOCAL_CONFIG_RU"
                if [ "$use_ad_blocking" = true ]; then target_url="$CONFIG_URL_RU"; else target_url="$CONFIG_URL_RU_NO_ADS"; fi
            else # Зарубежный сервер
                target_local_path="$LOCAL_CONFIG_EN"
                if [ "$use_ad_blocking" = true ]; then target_url="$CONFIG_URL_EN"; else target_url="$CONFIG_URL_EN_NO_ADS"; fi
            fi
            get_config "$target_url" "$target_local_path"
            should_apply_credentials=true
            ;;
        3) 
            if [ -f "$LOCAL_CONFIG_STD" ]; then cp "$LOCAL_CONFIG_STD" "$ADH_CONFIG_FILE"; else error "Файл стандартной конфигурации не найден."; return 1; fi 
            ;;
        4) 
            if [ -f "$LOCAL_CONFIG_USER" ]; then cp "$LOCAL_CONFIG_USER" "$ADH_CONFIG_FILE"; else error "Пользовательская резервная копия не найдена."; return 1; fi 
            ;;
    esac
    
    if [ "$should_apply_credentials" = true ]; then 
        apply_user_credentials "$ADH_CONFIG_FILE"
    fi
    
    force_session_ttl "$ADH_CONFIG_FILE"; systemctl restart "$ADH_SERVICE_NAME"; wait_for_adh_service
    success "Конфигурация успешно применена. Проверьте работу AdGuard Home."
}


# Тестирует работоспособность AdGuard Home (разрешение имен, блокировка, DNSSEC).
test_adh() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return 1; fi
    if [ "$1" == "--silent" ]; then set +e; dig @127.0.0.1 +time=2 +tries=2 +short ya.ru >/dev/null; local test_result=$?; true; set -e; return $test_result; fi

    info "Проверка работы AdGuard Home..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local all_tests_ok=true; local test_ok=false

    if dig @127.0.0.1 +time=2 +tries=2 ya.ru A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "1. ${C_GREEN}Успешно${C_RESET} получен IP (ya.ru)\n"; else printf "1. ${C_RED}Ошибка${C_RESET} при получении IP (ya.ru)\n"; all_tests_ok=false; fi
    if dig @127.0.0.1 +time=2 +tries=2 google.com A +short | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then printf "2. ${C_GREEN}Успешно${C_RESET} получен IP (google.com)\n"; else printf "2. ${C_RED}Ошибка${C_RESET} при получении IP (google.com)\n"; all_tests_ok=false; fi
    
    local ad_result; ad_result=$(dig @127.0.0.1 +time=2 +tries=2 doubleclick.net A +short)
    if [[ "$ad_result" == "0.0.0.0" || -z "$ad_result" ]]; then printf "3. ${C_GREEN}Успешно${C_RESET} заблокирован (doubleclick.net)\n"; else printf "3. ${C_RED}Ошибка${C_RESET} блокировки (doubleclick.net)\n"; all_tests_ok=false; fi
    
    local dnssec_valid_domains=("www.internic.net" "www.dnssec-tools.org" "www.verisign.com" "www.nlnetlabs.nl"); test_ok=false
    for domain in "${dnssec_valid_domains[@]}"; do if dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec | grep -q "flags:.* ad;"; then printf "4. ${C_GREEN}Успешно${C_RESET} пройден DNSSEC (валидная подпись на %s)\n" "$domain"; test_ok=true; break; fi; done
    if ! $test_ok; then printf "4. ${C_RED}Ошибка${C_RESET} DNSSEC (валидная подпись)\n"; all_tests_ok=false; fi

    local dnssec_invalid_domains=("dnssec-failed.org" "www.dnssec-failed.org" "brokendnssec.net" "dlv.isc.org"); test_ok=false
    for domain in "${dnssec_invalid_domains[@]}"; do
        set +e; local dnssec_fail_output; dnssec_fail_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec) ; true; set -e
        if [[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: SERVFAIL"* ]] || \
           ([[ "$dnssec_fail_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* ]] && [[ "$dnssec_fail_output" != *"flags:.* ad;"* ]]); then
            printf "5. ${C_GREEN}Успешно${C_RESET} пройден DNSSEC (невалидная подпись на %s)\n" "$domain"
            test_ok=true
            break
        fi
    done
    if ! $test_ok; then printf "5. ${C_RED}Ошибка${C_RESET} DNSSEC (невалидная подпись)\n"; all_tests_ok=false; fi
    
    local dnssec_insecure_domains=("example.com" "github.com" "iana.org" "icann.org"); test_ok=false
    for domain in "${dnssec_insecure_domains[@]}"; do
        local dnssec_insecure_output; dnssec_insecure_output=$(dig @127.0.0.1 +time=2 +tries=2 "$domain" +dnssec)
        if [[ "$dnssec_insecure_output" == *";; ->>HEADER<<- opcode: QUERY, status: NOERROR"* && "$dnssec_insecure_output" != *"flags:.* ad;"* ]]; then printf "6. ${C_GREEN}Успешно${C_RESET} пройден DNSSEC (отсутствующая подпись на %s)\n" "$domain"; test_ok=true; break; fi
    done
    if ! $test_ok; then printf "6. ${C_RED}Ошибка${C_RESET} DNSSEC (отсутствующая подпись)\n"; all_tests_ok=false; fi

    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    if $all_tests_ok; then
        return 0 
    else 
        if [ "$1" == "--silent" ]; then
            return 1
        else
            return 0
        fi
    fi
}

# Полностью удаляет AdGuard Home и все связанные с ним файлы.
uninstall_adh() {
    if ! is_adh_installed && [ ! -d "$ADH_DIR" ]; then warning "AdGuard Home не установлен."; return; fi; local force_uninstall=false; if [ "$1" == "--force" ]; then force_uninstall=true; fi
    if ! $force_uninstall && ! prompt_yes_no "Вы уверены, что хотите полностью удалить AdGuard Home?"; then info "Удаление отменено."; return 1; fi
    
    info "Удаление началось, подождите..."
    chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true; if is_service_installed; then systemctl disable --now set-dns.service 2>/dev/null || true; rm -f "$SERVICE_FILE_PATH" "$SET_DNS_SCRIPT_PATH"; fi
    if [ -x "$ADH_DIR/AdGuardHome" ]; then "$ADH_DIR/AdGuardHome" -s uninstall &>/dev/null; fi
    force_cleanup_remnants; restore_resolv_conf; chattr -i "$RESOLV_CONF_PATH" 2>/dev/null || true
    success "AdGuard Home полностью удален!"
}

# Переустанавливает AdGuard Home, выполняя удаление и последующую установку.
reinstall_adh() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return; fi
    if ! prompt_yes_no "Вы уверены, что хотите ПЕРЕУСТАНОВИТЬ AdGuard Home?"; then info "Переустановка отменена."; return 1; fi
    printf "\n"
    uninstall_adh --force
    printf "\n"
    install_adh
}

# Управляет службой AdGuard Home (start, stop, restart, status).
manage_service() {
    if ! is_adh_installed; then error "AdGuard Home не установлен."; return; fi
    set +e; systemctl "$1" "$ADH_SERVICE_NAME"; true; set -e
}

# Отображает главное меню и обрабатывает выбор пользователя.
main_menu() {
    while true; do
        clear; local menu_items=(); local menu_actions=()
        printf "${C_GREEN}AdGuard Home Easy Setup by Internet Helper${C_RESET}\n"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if is_adh_installed; then if is_adh_active; then printf "${C_GREEN}🟢 Работает${C_RESET}\n"; else printf "${C_YELLOW}🟡 Остановлен${C_RESET}\n"; fi; else printf "${C_RED}🔴 Не установлен${C_RESET}\n"; fi
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; local group_counts=()
        if is_adh_installed; then
            menu_items+=("Запустить AdGuard Home" "Остановить AdGuard Home" "Перезапустить AdGuard Home" "Показать статус AdGuard Home"); menu_actions+=("manage_service 'start'" "manage_service 'stop'" "manage_service 'restart'" "clear; manage_service 'status'"); group_counts+=(4)
            menu_items+=("Изменить конфигурацию" "Сделать резервную копию" "Проверить работу"); menu_actions+=("change_config" "create_user_backup" "test_adh"); group_counts+=(3)
            menu_items+=("Переустановить" "Удалить"); menu_actions+=("reinstall_adh" "uninstall_adh"); group_counts+=(2)
        else menu_items+=("Установить AdGuard Home"); menu_actions+=("install_adh"); group_counts+=(1); fi
        local item_counter=0; for group_size in "${group_counts[@]}"; do for (( i=0; i<group_size; i++ )); do echo "$((item_counter+1)). ${menu_items[item_counter]}"; item_counter=$((item_counter+1)); done; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; done
        echo "0. Выйти"; printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; read -p "Выберите действие: " menu_choice

        printf "\n"

        if [[ "$menu_choice" == "0" ]]; then exit 0; fi; if [[ ! "$menu_choice" =~ ^[0-9]+$ ]] || (( menu_choice < 1 || menu_choice > ${#menu_items[@]} )); then continue; fi
        
        local action_index=$((menu_choice - 1))
        
        set +e
        eval "${menu_actions[action_index]}"
        local return_code=$?
        true
        set -e
        
        if [[ "${menu_actions[action_index]}" != *"status"* && "${menu_actions[action_index]}" != *"manage_service"* && "$return_code" -ne 100 ]]; then
            printf "\n"; read -p "Нажмите Enter для продолжения..."
        fi
    done
}

# --- ТОЧКА ВХОДА В СКРИПТ ---
# Запускает начальные проверки и отображает главное меню.
initial_checks
main_menu