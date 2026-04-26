#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE="max-messenger:latest"
CONTAINER="max_messenger"
CONFIG_DIR="$HOME/.max"
LOG_DIR="${PROJECT_DIR}/logs"

# Изолированная сеть
NETWORK_NAME="max_isolated_network"
CONTAINER_IP="172.20.0.100"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# Проверка Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker не установлен"
    exit 1
fi

# Создание изолированной сети
if ! docker network inspect "$NETWORK_NAME" &> /dev/null; then
    log_info "Создание изолированной сети $NETWORK_NAME..."
    docker network create \
        --driver bridge \
        --subnet=172.20.0.0/16 \
        --gateway=172.20.0.1 \
        --opt com.docker.network.bridge.enable_icc=false \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        "$NETWORK_NAME"
    log_success "Изолированная сеть создана"
fi

# Проверка образа
if ! docker image inspect "$IMAGE" &> /dev/null; then
    log_error "Образ $IMAGE не найден"
    log_info "Выполните сборку: cd ${PROJECT_DIR}/docker && docker build -t ${IMAGE} ."
    exit 1
fi

log_info "Подготовка окружения для MAX Messenger"

# Остановка старого контейнера
if [ "$(docker ps -q -f name=^/${CONTAINER}$)" ]; then
    log_warning "Остановка запущенного контейнера..."
    docker stop "${CONTAINER}" >/dev/null 2>&1
    sleep 2
fi

if [ "$(docker ps -aq -f name=^/${CONTAINER}$)" ]; then
    docker rm -f "${CONTAINER}" >/dev/null 2>&1
fi

# Очистка файлов блокировки
if [ -d "$CONFIG_DIR" ]; then
    log_info "Сброс файлов блокировки мессенджера..."
    find "$CONFIG_DIR" -name "SingletonLock" -delete 2>/dev/null
    find "$CONFIG_DIR" -name "*.lock" -delete 2>/dev/null
fi

# Настройка X11
export DISPLAY=":0"
xhost +SI:localuser:root 2>/dev/null
log_success "Права X11 настроены"

# Проверка доступности дисплея
if command -v xdpyinfo &> /dev/null; then
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        log_success "Дисплей $DISPLAY доступен"
    else
        log_warning "Дисплей $DISPLAY не доступен"
    fi
fi

# Проверка GPU
GPU_ARGS=""
if command -v nvidia-smi &> /dev/null; then
    NVIDIA_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$NVIDIA_GPU" ]; then
        GPU_ARGS="--gpus all"
        log_success "NVIDIA GPU найдена: $NVIDIA_GPU"
    fi
elif [ -e /dev/dri ]; then
    GPU_ARGS="--device /dev/dri:/dev/dri"
    log_success "GPU устройства найдены (Intel/AMD)"
fi

# Настройка DBus
DBUS_ARGS=""
if [ -e "/run/user/1000/bus" ]; then
    DBUS_ARGS="-v /run/user/1000/bus:/run/user/1000/bus:ro -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
    log_success "DBus сокет найден"
fi

# Формирование опций безопасности
SECURITY_OPTS="--security-opt no-new-privileges:true --security-opt seccomp=${SCRIPT_DIR}/seccomp-max.json"

log_info "Запуск MAX Messenger в изолированном окружении..."
echo "---"

# Запуск с максимальной изоляцией (ВОССТАНОВЛЕНА read-only ФС)
docker run \
    --name "${CONTAINER}" \
    --rm \
    --network "${NETWORK_NAME}" \
    --ip "${CONTAINER_IP}" \
    \
    ${SECURITY_OPTS} \
    \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=128M \
    --tmpfs /run:rw,noexec,nosuid,size=64M \
    \
    --cap-drop ALL \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    \
    -e DISPLAY="${DISPLAY}" \
    -e QT_QPA_PLATFORM="xcb" \
    -e QT_X11_NO_MITSHM=1 \
    -e LIBGL_ALWAYS_SOFTWARE=0 \
    -e ELECTRON_NO_SANDBOX=1 \
    -e SECRETS_SERVICE_IGNORE=1 \
    \
    -v /tmp/.X11-unix/X0:/tmp/.X11-unix/X0:ro \
    -v "${CONFIG_DIR}":/home/maxuser/.config/max:rw \
    -v "${LOG_DIR}":/home/maxuser/logs:rw \
    \
    ${DBUS_ARGS} \
    ${GPU_ARGS} \
    \
    "${IMAGE}"

EXIT_CODE=$?

# Очистка прав X11
xhost - 2>/dev/null

if [ $EXIT_CODE -eq 0 ]; then
    log_success "Сессия MAX Messenger завершена"
else
    log_error "Ошибка: код $EXIT_CODE"
fi

exit $EXIT_CODE
