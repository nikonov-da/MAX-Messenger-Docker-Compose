#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Конфигурация
CONTAINER_NAME="max_messenger"
IMAGE_NAME="max-messenger:latest"
NETWORK_NAME="max_isolated_network"
SECCOMP_PROFILE="$SCRIPT_DIR/seccomp-max.json"
APPARMOR_PROFILE="docker-max-messenger"

# Определение пакетного менеджера
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    PKG_INSTALL="sudo dnf install -y"
    XHOST_PKG="xorg-x11-server-utils"
    MESA_PKG="mesa-demos"
    KEYRING_PKG="gnome-keyring"
    DOCKER_COMPOSE_PKG="docker-compose-plugin"
elif command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
    PKG_INSTALL="sudo apt install -y"
    XHOST_PKG="x11-xserver-utils"
    MESA_PKG="mesa-utils"
    KEYRING_PKG="gnome-keyring"
    DOCKER_COMPOSE_PKG="docker-compose-plugin"
else
    PKG_MANAGER="unknown"
fi

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Функции логирования
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            MAX Fix Tool - Восстановление v2.0              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 0. Остановка запущенного контейнера
echo -e "${GREEN}[0/10] Проверка запущенных контейнеров...${NC}"
if command -v docker &> /dev/null; then
    if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
        log_warning "Найден запущенный контейнер ${CONTAINER_NAME}"
        echo -e "  Остановка контейнера..."
        docker stop "${CONTAINER_NAME}" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "Контейнер ${CONTAINER_NAME} остановлен"
        else
            log_error "Не удалось остановить контейнер"
        fi
    else
        log_success "Запущенных контейнеров не найдено"
    fi

    # Удаление остановленного контейнера если есть
    if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
        log_info "Удаление старого контейнера..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
        log_success "Контейнер удалён"
    fi
else
    log_warning "Docker не установлен или недоступен"
fi

echo ""
echo -e "${GREEN}[1/10] Проверка Docker...${NC}"
if command -v docker &> /dev/null; then
    log_success "Docker установлен"
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    echo -e "  Версия: $DOCKER_VERSION"

    # Проверка Docker Compose
    if command -v docker compose &> /dev/null; then
        log_success "Docker Compose установлен"
    else
        log_warning "Docker Compose не установлен"
        echo -e "  Установка: $PKG_INSTALL $DOCKER_COMPOSE_PKG"
    fi
else
    log_error "Docker не установлен"
    echo -e "  Установка: $PKG_INSTALL docker-ce docker-ce-cli containerd.io"
fi

echo ""
echo -e "${GREEN}[2/10] Проверка изолированной сети...${NC}"
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    log_success "Изолированная сеть $NETWORK_NAME существует"
    NETWORK_INFO=$(docker network inspect "$NETWORK_NAME" 2>/dev/null)
    echo -e "  Подсеть: $(echo "$NETWORK_INFO" | grep -A2 "IPAM" | grep "Subnet" | awk -F'"' '{print $4}')"
    if echo "$NETWORK_INFO" | grep -q '"com.docker.network.bridge.enable_icc":"false"'; then
        log_success "  Межконтейнерное взаимодействие: ЗАПРЕЩЕНО"
    else
        log_warning "  Межконтейнерное взаимодействие: РАЗРЕШЕНО (небезопасно)"
    fi
else
    log_warning "Изолированная сеть $NETWORK_NAME не найдена"
    echo -e "  Создание сети..."
    docker network create \
        --driver bridge \
        --subnet=172.20.0.0/16 \
        --gateway=172.20.0.1 \
        --opt com.docker.network.bridge.enable_icc=false \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        "$NETWORK_NAME" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_success "Изолированная сеть создана"
    else
        log_error "Не удалось создать изолированную сеть"
    fi
fi

echo ""
echo -e "${GREEN}[3/10] Проверка X11...${NC}"
# Определение типа сессии
if [ -n "$WAYLAND_DISPLAY" ]; then
    log_warning "Обнаружен Wayland, рекомендуется переключиться на X11"
    log_info "Для переключения выберите 'Ubuntu on Xorg' при входе в систему"
fi

if [ -n "$DISPLAY" ]; then
    if command -v xhost &> /dev/null; then
        # Пробуем разные методы настройки прав
        xhost +SI:localuser:root 2>/dev/null
        if [ $? -eq 0 ]; then
            log_success "Права X11 настроены (режим: localuser:root)"
        else
            log_warning "Метод localuser:root не сработал, пробуем xhost +"
            xhost + 2>/dev/null
            if [ $? -eq 0 ]; then
                log_success "Права X11 настроены (режим: xhost +)"
            else
                log_error "Не удалось настроить права X11"
            fi
        fi
    else
        log_warning "xhost не установлен"
        echo -e "  Установка: $PKG_INSTALL $XHOST_PKG"
    fi
else
    log_warning "DISPLAY не установлен, устанавливаем :0"
    export DISPLAY=":0"
    echo -e "  DISPLAY=${DISPLAY}"
fi

# Проверка доступности дисплея
if command -v xdpyinfo &> /dev/null; then
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        log_success "Дисплей $DISPLAY доступен"
    else
        log_warning "Дисплей $DISPLAY не доступен"
        # Поиск доступного дисплея
        for d in :0 :1 :2 :3; do
            if xdpyinfo -display "$d" >/dev/null 2>&1; then
                export DISPLAY="$d"
                log_success "Найден работающий дисплей: $DISPLAY"
                break
            fi
        done
    fi
fi

echo ""
echo -e "${GREEN}[4/10] Проверка NVIDIA GPU и драйверов...${NC}"

# Проверка NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    log_success "NVIDIA GPU обнаружена"
    NVIDIA_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
    echo -e "  Видеокарта: $NVIDIA_GPU"
    echo -e "  Драйвер: $DRIVER_VERSION"

    # Проверка NVIDIA Container Toolkit
    if command -v nvidia-container-toolkit &> /dev/null; then
        log_success "NVIDIA Container Toolkit установлен"
    else
        log_warning "NVIDIA Container Toolkit не установлен"
        echo -e "  Установка: sudo dnf install nvidia-container-toolkit"
        echo -e "  Настройка: sudo nvidia-ctk runtime configure --runtime=docker"
        echo -e "  Перезапуск: sudo systemctl restart docker"
    fi

    # Проверка работает ли NVIDIA в Docker
    if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        log_success "NVIDIA GPU работает в Docker"
    else
        log_warning "NVIDIA GPU не работает в Docker"
        echo -e "  Выполните: sudo nvidia-ctk runtime configure --runtime=docker"
        echo -e "  Затем: sudo systemctl restart docker"
    fi
else
    log_warning "NVIDIA драйверы не установлены"
    echo -e "  Установка на Fedora: sudo dnf install akmod-nvidia"
    echo -e "  После установки перезагрузите компьютер"
fi

# Проверка устройств DRI (для Intel/AMD)
if [ -e /dev/dri ]; then
    log_success "GPU устройства найдены: /dev/dri"
    if [ -e /dev/dri/renderD128 ]; then
        log_success "  Render устройство: /dev/dri/renderD128"
    fi
    if [ -e /dev/dri/card0 ]; then
        log_success "  Карта: /dev/dri/card0"
    fi
fi

# Проверка OpenGL на хосте
if command -v glxinfo &> /dev/null; then
    GL_RENDERER=$(glxinfo -display "$DISPLAY" 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
    if [ -n "$GL_RENDERER" ]; then
        echo -e "  OpenGL рендерер: $GL_RENDERER"
        if echo "$GL_RENDERER" | grep -qi "nvidia"; then
            log_success "Аппаратное ускорение NVIDIA активно"
        elif echo "$GL_RENDERER" | grep -qi "llvmpipe"; then
            log_warning "Используется программный рендеринг (llvmpipe)"
            echo -e "  Установите драйверы: $PKG_INSTALL $MESA_PKG"
        else
            log_success "Аппаратное ускорение активно"
        fi
    fi
else
    log_warning "glxinfo не установлен"
    echo -e "  Установка: $PKG_INSTALL $MESA_PKG"
fi

# Настройка переменных окружения для GPU
echo -e "  Настройка GPU переменных..."
{
    echo ''
    echo '# MAX Messenger GPU settings'
    echo 'export LIBGL_ALWAYS_SOFTWARE=0'
    echo 'export MESA_GL_VERSION_OVERRIDE=4.5'
    echo 'export MESA_GLES_VERSION_OVERRIDE=3.2'
    echo 'export __GL_SYNC_TO_VBLANK=0'
    echo 'export __GL_SHADER_DISK_CACHE=1'
    echo 'export vblank_mode=0'
    echo 'export __GLX_VENDOR_LIBRARY_NAME=nvidia'
    echo 'export NVIDIA_VISIBLE_DEVICES=all'
    echo 'export NVIDIA_DRIVER_CAPABILITIES=all'
} >> ~/.profile 2>/dev/null
log_success "GPU переменные добавлены в ~/.profile"

echo ""
echo -e "${GREEN}[5/10] Проверка DBus...${NC}"
REAL_UID=$(id -u)
DBUS_SOCKET_PATH="/run/user/${REAL_UID}/bus"

if [ -e "$DBUS_SOCKET_PATH" ]; then
    log_success "DBus сокет найден: $DBUS_SOCKET_PATH"
else
    log_warning "DBus сокет не найден: $DBUS_SOCKET_PATH"

    # Попытка перезапустить DBus
    if systemctl --user is-active dbus >/dev/null 2>&1; then
        echo -e "  Перезапуск DBus сервиса..."
        systemctl --user restart dbus 2>/dev/null
        sleep 2
    else
        echo -e "  Запуск DBus сервиса..."
        systemctl --user start dbus 2>/dev/null
        sleep 2
    fi

    # Проверка после перезапуска
    if [ -e "$DBUS_SOCKET_PATH" ]; then
        log_success "DBus сокет восстановлен"
    else
        log_warning "DBus сокет не создан, запуск новой сессии"
        eval $(dbus-launch --sh-syntax 2>/dev/null)
        export DBUS_SESSION_BUS_ADDRESS
        log_success "DBus сессия запущена: $DBUS_SESSION_BUS_ADDRESS"
    fi
fi

# Проверка DBus в Docker
if command -v docker &> /dev/null && docker image inspect "$IMAGE_NAME" &> /dev/null; then
    log_info "Проверка DBus внутри Docker образа..."
    docker run --rm --entrypoint bash "$IMAGE_NAME" -c "dbus-launch --version" 2>/dev/null >/dev/null
    if [ $? -eq 0 ]; then
        log_success "DBus доступен внутри контейнера"
    else
        log_warning "DBus может отсутствовать в образе"
    fi
fi

echo ""
echo -e "${GREEN}[6/10] Проверка GNOME Keyring...${NC}"
KEYRING_PATH="/run/user/${REAL_UID}/keyring/control"

if [ -e "$KEYRING_PATH" ]; then
    log_success "GNOME Keyring работает"
else
    if command -v gnome-keyring-daemon &> /dev/null; then
        log_warning "GNOME Keyring не запущен, запускаем..."
        /usr/bin/gnome-keyring-daemon --start --components=secrets 2>/dev/null
        if [ -e "$KEYRING_PATH" ]; then
            log_success "GNOME Keyring запущен успешно"
        else
            log_warning "GNOME Keyring не запустился (не критично для работы)"
        fi
    else
        log_warning "GNOME Keyring не установлен"
        echo -e "  Установка: $PKG_INSTALL $KEYRING_PKG"
    fi
fi

echo ""
echo -e "${GREEN}[7/10] Проверка сокетов X11...${NC}"
X11_SOCKET="/tmp/.X11-unix/X0"
if [ -e "$X11_SOCKET" ]; then
    log_success "X11 сокет найден: $X11_SOCKET"
    if [ -r "$X11_SOCKET" ] && [ -w "$X11_SOCKET" ]; then
        log_success "Права доступа к X11 сокету корректны"
    else
        log_warning "Проблемы с правами доступа к X11 сокету"
        sudo chmod 666 "$X11_SOCKET" 2>/dev/null
    fi
else
    log_warning "X11 сокет не найден: $X11_SOCKET"
    for sock in /tmp/.X11-unix/X*; do
        if [ -e "$sock" ]; then
            log_success "Найден альтернативный сокет: $sock"
            ln -sf "$sock" "$X11_SOCKET" 2>/dev/null
            break
        fi
    done
fi

echo ""
echo -e "${GREEN}[8/10] Проверка звука...${NC}"
if [ -e /dev/snd ]; then
    log_success "Звуковые устройства найдены"
    if [ -e /dev/snd/pcmC0D0p ]; then
        log_success "  Звуковое устройство вывода: /dev/snd/pcmC0D0p"
    fi
else
    log_warning "Звуковые устройства не найдены"
fi

echo ""
echo -e "${GREEN}[9/10] Очистка блокировок MAX...${NC}"
CONFIG_DIR="$HOME/.max"
if [ -d "$CONFIG_DIR" ]; then
    SINGLETON_COUNT=$(find "$CONFIG_DIR" -name "Singleton*" 2>/dev/null | wc -l)
    if [ $SINGLETON_COUNT -gt 0 ]; then
        find "$CONFIG_DIR" -name "Singleton*" -delete 2>/dev/null
        log_success "Удалено $SINGLETON_COUNT файлов Singleton"
    fi

    LOCK_COUNT=$(find "$CONFIG_DIR" -name "*.lock" 2>/dev/null | wc -l)
    if [ $LOCK_COUNT -gt 0 ]; then
        find "$CONFIG_DIR" -name "*.lock" -delete 2>/dev/null
        log_success "Удалено $LOCK_COUNT lock файлов"
    fi

    # Очистка кэша
    if [ -d "$CONFIG_DIR/Cache" ]; then
        CACHE_SIZE=$(du -sh "$CONFIG_DIR/Cache" 2>/dev/null | cut -f1)
        if [ -n "$CACHE_SIZE" ]; then
            log_info "Размер кэша: $CACHE_SIZE"
            read -p "Очистить кэш? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$CONFIG_DIR/Cache" 2>/dev/null
                log_success "Кэш очищен"
            fi
        fi
    fi

    if [ $SINGLETON_COUNT -eq 0 ] && [ $LOCK_COUNT -eq 0 ]; then
        log_success "Блокировок не найдено"
    fi
else
    log_warning "Директория конфигурации не существует: $CONFIG_DIR"
fi

echo ""
echo -e "${GREEN}[10/10] Проверка Docker образа и безопасности...${NC}"
if command -v docker &> /dev/null; then
    if docker image inspect "$IMAGE_NAME" &> /dev/null; then
        log_success "Docker образ найден: $IMAGE_NAME"

        IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" --format='{{.Size}}' 2>/dev/null | numfmt --to=iec 2>/dev/null)
        if [ -n "$IMAGE_SIZE" ]; then
            echo -e "  Размер образа: $IMAGE_SIZE"
        fi

        # Проверка наличия Seccomp профиля
        if [ -f "$SECCOMP_PROFILE" ]; then
            log_success "Seccomp профиль найден: $SECCOMP_PROFILE"
        else
            log_warning "Seccomp профиль не найден: $SECCOMP_PROFILE"
            echo -e "  Безопасность может быть снижена"
        fi

        # Проверка AppArmor профиля
        if [ "$PKG_MANAGER" = "apt" ] && command -v apparmor_parser &> /dev/null; then
            if aa-status 2>/dev/null | grep -q "$APPARMOR_PROFILE"; then
                log_success "AppArmor профиль $APPARMOR_PROFILE загружен"
            else
                log_warning "AppArmor профиль $APPARMOR_PROFILE не загружен"
                echo -e "  Запустите: sudo apparmor_parser -r /etc/apparmor.d/$APPARMOR_PROFILE"
            fi
        fi

        # Проверка GPU библиотек в образе
        log_info "Проверка GPU библиотек в образе..."
        docker run --rm --gpus all --entrypoint bash "$IMAGE_NAME" -c "ldconfig -p 2>/dev/null | grep -q libGL && echo '  libGL найдена' || echo '  libGL не найдена'"
        docker run --rm --gpus all --entrypoint bash "$IMAGE_NAME" -c "ldconfig -p 2>/dev/null | grep -q libEGL && echo '  libEGL найдена' || echo '  libEGL не найдена'"

        # Проверка NVIDIA в образе
        if command -v nvidia-smi &> /dev/null; then
            docker run --rm --gpus all --entrypoint bash "$IMAGE_NAME" -c "nvidia-smi 2>/dev/null | head -1 || echo '  NVIDIA GPU не доступна'"
        fi
    else
        log_error "Docker образ не найден: $IMAGE_NAME"
        echo -e "  Сборка образа: cd ${PROJECT_DIR}/docker && docker build -t ${IMAGE_NAME} ."
    fi
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Восстановление завершено!${NC}"
echo ""
echo -e "Теперь можно запускать MAX Messenger:"
echo -e "  ${SCRIPT_DIR}/start-max.sh"
echo ""
echo -e "Если проблемы сохраняются:"
echo -e "  1. Переключитесь на X11 сессию (выйдите и выберите 'Ubuntu on Xorg')"
echo -e "  2. Перезагрузите компьютер"
echo -e "  3. Запустите диагностику: ${SCRIPT_DIR}/max-debug.sh"
echo -e "  4. Проверьте GPU: nvidia-smi или glxinfo | grep 'OpenGL renderer'"
echo -e "  5. Проверьте Docker: docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi"
echo -e "  6. Проверьте изоляцию: docker network inspect $NETWORK_NAME"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Задержка для чтения вывода
if [ -t 0 ]; then
    echo ""
    read -p "Нажмите Enter для выхода..." -t 5
fi
