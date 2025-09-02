#!/bin/bash

# WireGuard Client Setup Script for Ubuntu 24.04
# Автор: Assistant
# Версия: 1.4

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_header() {
    echo -e "${BLUE}================================${NC}" >&2
    echo -e "${BLUE}$1${NC}" >&2
    echo -e "${BLUE}================================${NC}" >&2
}

# Проверка запуска от root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от имени root"
        exit 1
    fi
}

# Установка WireGuard
install_wireguard() {
    print_header "УСТАНОВКА WIREGUARD"
    
    print_message "Обновление списка пакетов..."
    apt update -y
    
    print_message "Установка WireGuard..."
    apt install -y wireguard resolvconf
    
    print_message "WireGuard успешно установлен!"
}

# Проверка валидности конфига
check_config_validity() {
    local interface=$1
    local config_file="/etc/wireguard/$interface.conf"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Проверяем синтаксис конфига
    if wg-quick strip "$interface" > /dev/null 2>&1; then
        # Проверяем наличие обязательных секций
        if grep -q "\[Interface\]" "$config_file" && grep -q "\[Peer\]" "$config_file"; then
            return 0
        fi
    fi
    
    return 1
}

# Поиск существующих конфигов
find_existing_configs() {
    local configs=()
    
    for config in /etc/wireguard/*.conf; do
        if [[ -f "$config" ]]; then
            interface=$(basename "$config" .conf)
            if check_config_validity "$interface"; then
                configs+=("$interface")
            fi
        fi
    done
    
    echo "${configs[@]}"
}

# Восстановление существующего конфига
restore_existing_config() {
    local interface=$1
    
    print_header "ВОССТАНОВЛЕНИЕ ИНТЕРФЕЙСА $interface"
    
    if check_config_validity "$interface"; then
        print_message "Конфигурация $interface валидна, запускаем..."
        
        # Включаем автозапуск
        systemctl enable wg-quick@$interface.service
        
        # Запускаем сервис
        systemctl start wg-quick@$interface.service
        
        # Проверка статуса
        sleep 2
        if systemctl is-active --quiet wg-quick@$interface.service; then
            print_message "WireGuard интерфейс $interface успешно восстановлен!"
            show_status
            return 0
        else
            print_error "Ошибка при запуске интерфейса $interface"
            systemctl status wg-quick@$interface.service --no-pager
            return 1
        fi
    else
        print_error "Конфигурация $interface невалидна!"
        return 1
    fi
}

# Функция для ввода конфига целиком
input_full_config() {
    # Выводим заголовок только в stderr
    echo -e "${BLUE}================================${NC}" >&2
    echo -e "${BLUE}ВВОД ПОЛНОГО КОНФИГА${NC}" >&2
    echo -e "${BLUE}================================${NC}" >&2
    
    echo "" >&2
    echo -e "${YELLOW}Вставьте полный конфиг WireGuard (после ввода нажмите Ctrl+D):${NC}" >&2
    echo "" >&2
    
    # Читаем многострочный ввод
    config_content=$(cat)
    
    # Удаляем лишние пустые строки
    config_content=$(echo "$config_content" | sed '/^[[:space:]]*$/d')
    
    if [[ -z "$config_content" ]]; then
        echo -e "${RED}[ERROR]${NC} Конфигурация пуста!" >&2
        return 1
    fi
    
    # Проверяем наличие обязательных секций
    if ! echo "$config_content" | grep -q "\[Interface\]"; then
        echo -e "${RED}[ERROR]${NC} Конфигурация не содержит секцию [Interface]!" >&2
        return 1
    fi
    
    if ! echo "$config_content" | grep -q "\[Peer\]"; then
        echo -e "${RED}[ERROR]${NC} Конфигурация не содержит секцию [Peer]!" >&2
        return 1
    fi
    
    echo -e "${GREEN}[INFO]${NC} Конфигурация успешно получена" >&2
    echo "$config_content"
    return 0
}

# Функция для ввода параметров по отдельности
input_manual_config() {
    print_header "РУЧНОЙ ВВОД ПАРАМЕТРОВ"
    
    # Генерация приватного ключа для клиента
    print_message "Генерация приватного ключа клиента..."
    private_key=$(wg genkey)
    public_key=$(echo "$private_key" | wg pubkey)
    
    print_message "Сгенерированный публичный ключ клиента: $public_key"
    print_warning "ВАЖНО: Добавьте этот публичный ключ на ваш WireGuard сервер!"
    echo ""
    
    # Ввод параметров
    read -p "Введите адрес сервера (например, xray.firewing.ru): " server_address
    read -p "Введите порт сервера (например, 51388): " server_port
    read -p "Введите публичный ключ сервера: " server_public_key
    read -p "Введите IP-адрес клиента (например, 10.0.0.2/32): " client_ip
    read -p "Введите DNS сервера (например, 1.1.1.1, 1.0.0.1) [опционально]: " dns_servers
    read -p "Введите разрешенные IP (например, 0.0.0.0/0 для всего трафика): " allowed_ips
    read -p "Введите MTU (по умолчанию 1420): " mtu
    mtu=${mtu:-1420}
    
    # Дополнительные параметры
    read -p "Введите PresharedKey [опционально]: " preshared_key
    read -p "Включить KeepAlive? (y/n) [по умолчанию n]: " keepalive_choice
    
    keepalive=""
    if [[ "$keepalive_choice" == "y" || "$keepalive_choice" == "Y" ]]; then
        read -p "Введите интервал KeepAlive в секундах (например, 25): " keepalive_interval
        keepalive="PersistentKeepalive = $keepalive_interval"
    fi
    
    # Формирование конфига
    config_content="[Interface]
PrivateKey = $private_key
Address = $client_ip
DNS = ${dns_servers:-1.1.1.1, 1.0.0.1}
MTU = $mtu

[Peer]
PublicKey = $server_public_key
Endpoint = $server_address:$server_port
AllowedIPs = $allowed_ips"

    if [[ -n "$preshared_key" ]]; then
        config_content+="
PresharedKey = $preshared_key"
    fi
    
    if [[ -n "$keepalive" ]]; then
        config_content+="
$keepalive"
    fi
    
    echo "$config_content"
}

# Основное меню
main_menu() {
    print_header "НАСТРОЙКА КОНФИГУРАЦИИ WIREGUARD"
    echo "1) Ввести полный конфиг" >&2
    echo "2) Ввести параметры вручную" >&2
    echo -e "${YELLOW}Выберите способ настройки (1 или 2):${NC} " >&2
    
    read -r choice
    
    case $choice in
        1)
            config_content=$(input_full_config)
            if [ $? -ne 0 ]; then
                exit 1
            fi
            ;;
        2)
            config_content=$(input_manual_config)
            ;;
        *)
            print_error "Неверный выбор. Используется ручной ввод."
            config_content=$(input_manual_config)
            ;;
    esac
}

# Создание конфигурационного файла
create_config() {
    interface_name="wg0"
    print_message "Используется интерфейс: $interface_name"
    
    config_file="/etc/wireguard/$interface_name.conf"
    
    # Проверяем, существует ли уже конфиг
    if [[ -f "$config_file" ]]; then
        print_warning "Конфигурационный файл $config_file уже существует!"
        read -p "Перезаписать? (y/n): " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            print_error "Отмена создания конфигурации"
            exit 1
        fi
        # Останавливаем существующий интерфейс перед перезаписью
        if systemctl is-active --quiet wg-quick@$interface_name.service; then
            print_message "Останавливаем существующее соединение..."
            systemctl stop wg-quick@$interface_name.service
        fi
    fi
    
    print_message "Создание конфигурационного файла $config_file..."
    
    # Проверяем, что конфиг не пустой
    if [[ -z "$config_content" ]]; then
        print_error "Конфигурация пуста!"
        exit 1
    fi
    
    # Сохраняем конфиг в файл
    echo "$config_content" > "$config_file"
    chmod 600 "$config_file"
    
    print_message "Конфигурационный файл создан!"
    
    # Проверяем синтаксис конфига
    print_message "Проверка синтаксиса конфигурации..."
    if wg-quick strip "$interface_name" > /dev/null 2>&1; then
        print_message "Синтаксис конфигурации корректен"
    else
        print_error "Ошибка в конфигурации! Проверьте файл $config_file"
        print_message "Содержимое файла:"
        cat "$config_file"
        exit 1
    fi
}

# Настройка автозапуска
setup_autostart() {
    print_header "НАСТРОЙКА АВТОЗАПУСКА"
    
    print_message "Включение автозапуска WireGuard..."
    systemctl enable wg-quick@$interface_name.service
    
    print_message "Запуск WireGuard..."
    systemctl start wg-quick@$interface_name.service
    
    # Проверка статуса
    sleep 2
    if systemctl is-active --quiet wg-quick@$interface_name.service; then
        print_message "WireGuard успешно запущен!"
    else
        print_error "Ошибка при запуске WireGuard. Проверьте конфигурацию."
        systemctl status wg-quick@$interface_name.service --no-pager
        exit 1
    fi
}

# Показать статус соединения
show_status() {
    print_header "СТАТУС СОЕДИНЕНИЯ"
    
    print_message "Статус интерфейса:"
    wg show 2>/dev/null || print_warning "Интерфейс WireGuard не активен"
    
    print_message "Статус сервиса:"
    systemctl status wg-quick@$interface_name.service --no-pager
    
    print_message "Проверка IP-адреса:"
    ip addr show $interface_name 2>/dev/null || print_warning "Интерфейс $interface_name не найден"
}

# Функция для удаления только интерфейса (без конфига)
delete_interface_only() {
    print_header "УДАЛЕНИЕ ТОЛЬКО ИНТЕРФЕЙСА"
    
    print_message "Остановка соединения..."
    systemctl stop wg-quick@$interface_name.service 2>/dev/null || true
    
    # Проверяем, существует ли интерфейс и удаляем его
    if ip link show $interface_name >/dev/null 2>&1; then
        print_message "Удаление интерфейса $interface_name..."
        ip link delete $interface_name
        print_message "Интерфейс $interface_name удален"
    else
        print_message "Интерфейс $interface_name не активен"
    fi
    
    print_message "Конфигурационный файл сохранен: /etc/wireguard/$interface_name.conf"
    print_message "Для восстановления соединения используйте: systemctl start wg-quick@$interface_name"
}

# Функция для удаления интерфейса и конфига
delete_interface_with_config() {
    print_header "УДАЛЕНИЕ ИНТЕРФЕЙСА И КОНФИГА"
    
    print_message "Остановка соединения..."
    systemctl stop wg-quick@$interface_name.service 2>/dev/null || true
    
    print_message "Отключение автозапуска..."
    systemctl disable wg-quick@$interface_name.service 2>/dev/null || true
    
    # Проверяем, существует ли интерфейс и удаляем его
    if ip link show $interface_name >/dev/null 2>&1; then
        print_message "Удаление интерфейса $interface_name..."
        ip link delete $interface_name
        print_message "Интерфейс $interface_name удален"
    else
        print_message "Интерфейс $interface_name не активен"
    fi
    
    print_message "Удаление конфигурационного файла..."
    config_file="/etc/wireguard/$interface_name.conf"
    if [[ -f "$config_file" ]]; then
        rm -f "$config_file"
        print_message "Конфигурационный файл $config_file удален"
    else
        print_warning "Конфигурационный файл $config_file не найден"
    fi
    
    print_message "Полное удаление завершено!"
}

# Функция для управления соединением
manage_connection() {
    print_header "УПРАВЛЕНИЕ СОЕДИНЕНИЕМ"
    echo "1) Запустить соединение" >&2
    echo "2) Остановить соединение" >&2
    echo "3) Перезапустить соединение" >&2
    echo "4) Показать статус" >&2
    echo "5) Показать конфигурацию" >&2
    echo "6) Удалить только интерфейс (сохранить конфиг)" >&2
    echo "7) Удалить интерфейс и конфиг" >&2
    echo -e "${YELLOW}Выберите действие (1-7):${NC} " >&2
    
    read -r action
    
    case $action in
        1)
            systemctl start wg-quick@$interface_name.service
            print_message "Соединение запущено"
            ;;
        2)
            systemctl stop wg-quick@$interface_name.service
            print_message "Соединение остановлено"
            ;;
        3)
            systemctl restart wg-quick@$interface_name.service
            print_message "Соединение перезапущено"
            ;;
        4)
            show_status
            ;;
        5)
            print_message "Конфигурация $interface_name:"
            cat /etc/wireguard/$interface_name.conf
            ;;
        6)
            delete_interface_only
            ;;
        7)
            delete_interface_with_config
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
}

# Функция для выбора интерфейса
select_interface() {
    local available_interfaces=()
    
    # Ищем все валидные конфиги WireGuard
    for config in /etc/wireguard/*.conf; do
        if [[ -f "$config" ]]; then
            interface=$(basename "$config" .conf)
            if check_config_validity "$interface"; then
                available_interfaces+=("$interface")
            fi
        fi
    done
    
    if [[ ${#available_interfaces[@]} -eq 0 ]]; then
        print_error "Валидные конфигурационные файлы WireGuard не найдены!"
        exit 1
    fi
    
    print_header "ВЫБОР ИНТЕРФЕЙСА"
    echo "Доступные интерфейсы:" >&2
    for i in "${!available_interfaces[@]}"; do
        echo "$((i+1))) ${available_interfaces[$i]}" >&2
    done
    
    echo -e "${YELLOW}Выберите интерфейс (1-${#available_interfaces[@]}):${NC} " >&2
    read -r choice
    
    if [[ $choice -ge 1 && $choice -le ${#available_interfaces[@]} ]]; then
        interface_name="${available_interfaces[$((choice-1))]}"
        print_message "Выбран интерфейс: $interface_name"
    else
        print_error "Неверный выбор"
        exit 1
    fi
}

# Главная функция
main() {
    print_header "WIREGUARD CLIENT SETUP FOR UBUNTU 24.04"
    
    check_root
    
    # Проверяем, установлен ли уже WireGuard
    if ! command -v wg &> /dev/null; then
        install_wireguard
    else
        print_message "WireGuard уже установлен"
    fi
    
    # Проверяем наличие существующих конфигов
    existing_configs=($(find_existing_configs))
    
    echo "" >&2
    echo "1) Настроить новое соединение" >&2
    echo "2) Управлять существующим соединением" >&2
    echo "3) Удалить интерфейс и/или конфиг" >&2
    
    # Если есть существующие конфиги, предлагаем восстановить
    if [[ ${#existing_configs[@]} -gt 0 ]]; then
        echo "4) Восстановить существующее соединение" >&2
    fi
    
    echo -e "${YELLOW}Выберите действие (1-${#existing_configs[@]} -gt 0 ? 4 : 3):${NC} " >&2
    
    read -r main_choice
    
    case $main_choice in
        1)
            # Если есть существующие конфиги, предлагаем восстановить вместо создания нового
            if [[ ${#existing_configs[@]} -gt 0 ]]; then
                print_warning "Обнаружены существующие конфигурации: ${existing_configs[*]}"
                read -p "Создать новое соединение вместо восстановления существующего? (y/n): " create_new
                if [[ "$create_new" != "y" && "$create_new" != "Y" ]]; then
                    print_message "Переход к восстановлению существующего соединения..."
                    interface_name=${existing_configs[0]}
                    if [[ ${#existing_configs[@]} -gt 1 ]]; then
                        select_interface
                    fi
                    restore_existing_config "$interface_name"
                    exit 0
                fi
            fi
            
            main_menu
            create_config
            setup_autostart
            show_status
            
            print_header "УСТАНОВКА ЗАВЕРШЕНА"
            print_message "WireGuard клиент успешно настроен!"
            print_message "Для управления используйте команды:"
            echo -e "  ${BLUE}systemctl start wg-quick@wg0${NC}   - запустить" >&2
            echo -e "  ${BLUE}systemctl stop wg-quick@wg0${NC}    - остановить" >&2
            echo -e "  ${BLUE}systemctl restart wg-quick@wg0${NC} - перезапустить" >&2
            echo -e "  ${BLUE}wg show${NC}                        - показать статус" >&2
            echo -e "  ${BLUE}systemctl status wg-quick@wg0${NC}  - статус сервиса" >&2
            ;;
        2)
            select_interface
            manage_connection
            ;;
        3)
            select_interface
            print_header "ВЫБЕРТЕ ТИП УДАЛЕНИЯ"
            echo "1) Удалить только интерфейс (сохранить конфиг)" >&2
            echo "2) Удалить интерфейс и конфиг" >&2
            echo -e "${YELLOW}Выберите действие (1-2):${NC} " >&2
            
            read -r delete_choice
            case $delete_choice in
                1)
                    delete_interface_only
                    ;;
                2)
                    delete_interface_with_config
                    ;;
                *)
                    print_error "Неверный выбор"
                    ;;
            esac
            ;;
        4)
            if [[ ${#existing_configs[@]} -gt 0 ]]; then
                if [[ ${#existing_configs[@]} -eq 1 ]]; then
                    interface_name=${existing_configs[0]}
                    restore_existing_config "$interface_name"
                else
                    select_interface
                    restore_existing_config "$interface_name"
                fi
            else
                print_error "Нет доступных конфигураций для восстановления"
                exit 1
            fi
            ;;
        *)
            print_error "Неверный выбор"
            exit 1
            ;;
    esac
}

# Обработка сигналов
trap 'print_error "Скрипт прерван пользователем"; exit 1' INT TERM

# Запуск основной функции
main "$@"
