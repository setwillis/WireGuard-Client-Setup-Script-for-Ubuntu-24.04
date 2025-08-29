#!/bin/bash

# WireGuard Client Setup Script for Ubuntu 24.04
# Автор: Assistant
# Версия: 1.0

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
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

# Функция для ввода конфига целиком
input_full_config() {
    echo ""
    echo -e "${YELLOW}Скопируйте и вставьте ваш WireGuard конфиг, затем нажмите Enter и Ctrl+D:${NC}"
    echo ""
    
    # Читаем ввод в переменную построчно
    config_lines=()
    echo -e "${BLUE}> ${NC}"
    
    while IFS= read -r line; do
        # Пропускаем служебные строки скрипта
        if [[ ! "$line" =~ ^=+$ ]] && \
           [[ ! "$line" =~ "НАСТРОЙКА КОНФИГУРАЦИИ" ]] && \
           [[ ! "$line" =~ "ВВОД ПОЛНОГО КОНФИГА" ]] && \
           [[ ! "$line" =~ "Вставьте полный конфиг" ]] && \
           [[ ! "$line" =~ "Выберите способ" ]] && \
           [[ ! "$line" =~ "1) Ввести" ]] && \
           [[ ! "$line" =~ "2) Ввести" ]]; then
            config_lines+=("$line")
        fi
    done
    
    # Объединяем строки в конфиг
    config_content=""
    for line in "${config_lines[@]}"; do
        if [[ -n "$line" ]]; then
            config_content+="$line"

# Функция для ввода параметров по отдельности
input_manual_config() {
    print_header "РУЧНОЙ ВВОД ПАРАМЕТРОВ"
    
    # Генерация приватного ключа для клиента
    print_message "Генерация приватного ключа клиента..."
    private_key=$(wg genkey)
    public_key=$(echo "$private_key" | wg pubkey)
    
    print_message "Сгенерированный публичный ключ клиента: $public_key"
    print_warning "ВАЖНО: Добавьте этот публичный ключ на ваш WireGuard сервер!"
    
    # Ввод параметров
    read -p "Введите адрес сервера (например, xray.firewing.ru): " server_address
    read -p "Введите порт сервера (например, 51388): " server_port
    read -p "Введите публичный ключ сервера: " server_public_key
    read -p "Введите IP-адрес клиента (например, 10.0.0.2/32): " client_ip
    read -p "Введите DNS сервера (например, 1.1.1.1, 1.0.0.1) [опционально]: " dns_servers
    read -p "Введите разрешенные IP (например, 0.0.0.0/0 для всего трафика): " allowed_ips
    read -p "Введите MTU (по умолчанию 1420): " mtu
    mtu=${mtu:-1420}
    
    # Дополнительные параметры для xray-ui
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
        config_content+="\nPresharedKey = $preshared_key"
    fi
    
    if [[ -n "$keepalive" ]]; then
        config_content+="\n$keepalive"
    fi
    
    return 0
}

# Основное меню
main_menu() {
    print_header "НАСТРОЙКА КОНФИГУРАЦИИ WIREGUARD"
    echo "1) Ввести полный конфиг"
    echo "2) Ввести параметры вручную"
    echo -e "${YELLOW}Выберите способ настройки (1 или 2):${NC} "
    
    read -r choice
    
    case $choice in
        1)
            if input_full_config; then
                return 0
            else
                print_error "Ошибка при вводе конфигурации"
                exit 1
            fi
            ;;
        2)
            if input_manual_config; then
                return 0
            else
                print_error "Ошибка при создании конфигурации"
                exit 1
            fi
            ;;
        *)
            print_error "Неверный выбор. Используется ручной ввод."
            if input_manual_config; then
                return 0
            else
                exit 1
            fi
            ;;
    esac
}

# Создание конфигурационного файла
create_config() {
    interface_name="wg0"
    print_message "Используется интерфейс: $interface_name"
    
    config_file="/etc/wireguard/$interface_name.conf"
    
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
    systemctl enable wg-quick@$interface_name
    
    print_message "Запуск WireGuard..."
    systemctl start wg-quick@$interface_name
    
    # Проверка статуса
    if systemctl is-active --quiet wg-quick@$interface_name; then
        print_message "WireGuard успешно запущен!"
    else
        print_error "Ошибка при запуске WireGuard. Проверьте конфигурацию."
        systemctl status wg-quick@$interface_name
        exit 1
    fi
}

# Показать статус соединения
show_status() {
    print_header "СТАТУС СОЕДИНЕНИЯ"
    
    print_message "Статус интерфейса:"
    wg show
    
    print_message "Статус сервиса:"
    systemctl status wg-quick@$interface_name --no-pager
    
    print_message "Проверка IP-адреса:"
    ip addr show $interface_name 2>/dev/null || print_warning "Интерфейс $interface_name не найден"
}

# Функция для управления соединением
manage_connection() {
    print_header "УПРАВЛЕНИЕ СОЕДИНЕНИЕМ"
    echo "1) Запустить соединение"
    echo "2) Остановить соединение"
    echo "3) Перезапустить соединение"
    echo "4) Показать статус"
    echo "5) Показать конфигурацию"
    echo -e "${YELLOW}Выберите действие (1-5):${NC} "
    
    read -r action
    
    case $action in
        1)
            systemctl start wg-quick@$interface_name
            print_message "Соединение запущено"
            ;;
        2)
            systemctl stop wg-quick@$interface_name
            print_message "Соединение остановлено"
            ;;
        3)
            systemctl restart wg-quick@$interface_name
            print_message "Соединение перезапущено"
            ;;
        4)
            show_status
            ;;
        5)
            print_message "Конфигурация $interface_name:"
            cat /etc/wireguard/$interface_name.conf
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
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
    
    echo ""
    echo "1) Настроить новое соединение"
    echo "2) Управлять существующим соединением"
    echo -e "${YELLOW}Выберите действие (1 или 2):${NC} "
    
    read -r main_choice
    
    case $main_choice in
        1)
            main_menu
            create_config
            setup_autostart
            show_status
            
            print_header "УСТАНОВКА ЗАВЕРШЕНА"
            print_message "WireGuard клиент успешно настроен!"
            print_message "Для управления используйте команды:"
            echo -e "  ${BLUE}systemctl start wg-quick@$interface_name${NC}   - запустить"
            echo -e "  ${BLUE}systemctl stop wg-quick@$interface_name${NC}    - остановить"
            echo -e "  ${BLUE}systemctl restart wg-quick@$interface_name${NC} - перезапустить"
            echo -e "  ${BLUE}wg show${NC}                                    - показать статус"
            echo -e "  ${BLUE}systemctl status wg-quick@$interface_name${NC}  - статус сервиса"
            ;;
        2)
            interface_name="wg0"
            print_message "Используется интерфейс по умолчанию: $interface_name"
            if [[ -f "/etc/wireguard/$interface_name.conf" ]]; then
                manage_connection
            else
                print_error "Конфигурация $interface_name не найдена"
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
main "$@"\n'
        fi
    done
    
    # Удаляем лишние пустые строки в конце
    config_content=$(echo -n "$config_content" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
    
    if [[ -z "$config_content" ]]; then
        print_error "Конфигурация пуста!"
        return 1
    fi
    
    # Проверяем наличие обязательных секций
    if ! echo "$config_content" | grep -q "\[Interface\]"; then
        print_error "Конфигурация не содержит секцию [Interface]!"
        return 1
    fi
    
    if ! echo "$config_content" | grep -q "\[Peer\]"; then
        print_error "Конфигурация не содержит секцию [Peer]!"
        return 1
    fi
    
    print_message "Конфигурация успешно получена"
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
    
    # Ввод параметров
    read -p "Введите адрес сервера (например, xray.firewing.ru): " server_address
    read -p "Введите порт сервера (например, 51388): " server_port
    read -p "Введите публичный ключ сервера: " server_public_key
    read -p "Введите IP-адрес клиента (например, 10.0.0.2/32): " client_ip
    read -p "Введите DNS сервера (например, 1.1.1.1, 1.0.0.1) [опционально]: " dns_servers
    read -p "Введите разрешенные IP (например, 0.0.0.0/0 для всего трафика): " allowed_ips
    read -p "Введите MTU (по умолчанию 1420): " mtu
    mtu=${mtu:-1420}
    
    # Дополнительные параметры для xray-ui
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
        config_content+="\nPresharedKey = $preshared_key"
    fi
    
    if [[ -n "$keepalive" ]]; then
        config_content+="\n$keepalive"
    fi
    
    echo -e "$config_content"
}

# Основное меню
main_menu() {
    print_header "НАСТРОЙКА КОНФИГУРАЦИИ WIREGUARD"
    echo "1) Ввести полный конфиг"
    echo "2) Ввести параметры вручную"
    echo -e "${YELLOW}Выберите способ настройки (1 или 2):${NC} "
    
    read -r choice
    
    case $choice in
        1)
            config_content=$(input_full_config)
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
    systemctl enable wg-quick@$interface_name
    
    print_message "Запуск WireGuard..."
    systemctl start wg-quick@$interface_name
    
    # Проверка статуса
    if systemctl is-active --quiet wg-quick@$interface_name; then
        print_message "WireGuard успешно запущен!"
    else
        print_error "Ошибка при запуске WireGuard. Проверьте конфигурацию."
        systemctl status wg-quick@$interface_name
        exit 1
    fi
}

# Показать статус соединения
show_status() {
    print_header "СТАТУС СОЕДИНЕНИЯ"
    
    print_message "Статус интерфейса:"
    wg show
    
    print_message "Статус сервиса:"
    systemctl status wg-quick@$interface_name --no-pager
    
    print_message "Проверка IP-адреса:"
    ip addr show $interface_name 2>/dev/null || print_warning "Интерфейс $interface_name не найден"
}

# Функция для управления соединением
manage_connection() {
    print_header "УПРАВЛЕНИЕ СОЕДИНЕНИЕМ"
    echo "1) Запустить соединение"
    echo "2) Остановить соединение"
    echo "3) Перезапустить соединение"
    echo "4) Показать статус"
    echo "5) Показать конфигурацию"
    echo -e "${YELLOW}Выберите действие (1-5):${NC} "
    
    read -r action
    
    case $action in
        1)
            systemctl start wg-quick@$interface_name
            print_message "Соединение запущено"
            ;;
        2)
            systemctl stop wg-quick@$interface_name
            print_message "Соединение остановлено"
            ;;
        3)
            systemctl restart wg-quick@$interface_name
            print_message "Соединение перезапущено"
            ;;
        4)
            show_status
            ;;
        5)
            print_message "Конфигурация $interface_name:"
            cat /etc/wireguard/$interface_name.conf
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
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
    
    echo ""
    echo "1) Настроить новое соединение"
    echo "2) Управлять существующим соединением"
    echo -e "${YELLOW}Выберите действие (1 или 2):${NC} "
    
    read -r main_choice
    
    case $main_choice in
        1)
            main_menu
            create_config
            setup_autostart
            show_status
            
            print_header "УСТАНОВКА ЗАВЕРШЕНА"
            print_message "WireGuard клиент успешно настроен!"
            print_message "Для управления используйте команды:"
            echo -e "  ${BLUE}systemctl start wg-quick@$interface_name${NC}   - запустить"
            echo -e "  ${BLUE}systemctl stop wg-quick@$interface_name${NC}    - остановить"
            echo -e "  ${BLUE}systemctl restart wg-quick@$interface_name${NC} - перезапустить"
            echo -e "  ${BLUE}wg show${NC}                                    - показать статус"
            echo -e "  ${BLUE}systemctl status wg-quick@$interface_name${NC}  - статус сервиса"
            ;;
        2)
            interface_name="wg0"
            print_message "Используется интерфейс по умолчанию: $interface_name"
            if [[ -f "/etc/wireguard/$interface_name.conf" ]]; then
                manage_connection
            else
                print_error "Конфигурация $interface_name не найдена"
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
