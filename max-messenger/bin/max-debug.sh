#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="${PROJECT_DIR}/docker"
CONFIG_DIR="$HOME/.max"
LOG_DIR="${PROJECT_DIR}/logs"

IMAGE="max-messenger:latest"
CONTAINER_NAME="max_messenger"
NETWORK_NAME="max_isolated_network"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              MAX Messenger Debug Tool v2.0                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Проверка системы
echo -e "${GREEN}=== 1. Информация о системе ===${NC}"
echo "ОС: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "Ядро: $(uname -r)"
echo "Архитектура: $(uname -m)"
echo "Пользователь: $(whoami)"
echo "UID: $(id -u)"
echo "Тип сессии: ${XDG_SESSION_TYPE:-не определен}"
echo "Менеджер пакетов: $(command -v dnf &>/dev/null && echo "dnf (Fedora)" || echo "apt (Ubuntu/Debian)")"
echo ""

# 2. Проверка Docker
echo -e "${GREEN}=== 2. Проверка Docker ===${NC}"
if command -v docker &> /dev/null; then
    echo "Docker: установлен"
    echo "Версия: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'недоступно')"
    echo "Docker Compose: $(docker compose version --short 2>/dev/null || echo 'недоступен')"

    # Проверка NVIDIA Container Toolkit
    if command -v nvidia-container-toolkit &> /dev/null; then
        echo -e "${GREEN}✓ NVIDIA Container Toolkit установлен${NC}"
    else
        echo -e "${YELLOW}⚠ NVIDIA Container Toolkit не установлен${NC}"
        echo "    Установка: sudo dnf install nvidia-container-toolkit"
    fi

    # Проверка runtime
    echo "Docker runtime: $(docker info 2>/dev/null | grep -i "Default Runtime" | awk '{print $3}')"
else
    echo -e "${RED}✗ Docker не установлен!${NC}"
fi
echo ""

# 3. Проверка изолированной сети
echo -e "${GREEN}=== 3. Проверка изолированной сети ===${NC}"
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    echo -e "${GREEN}✓ Сеть $NETWORK_NAME существует${NC}"
    NETWORK_INFO=$(docker network inspect "$NETWORK_NAME" 2>/dev/null)
    echo "  Подсеть: $(echo "$NETWORK_INFO" | grep -A2 "IPAM" | grep "Subnet" | awk -F'"' '{print $4}')"
    echo "  Межконтейнерное взаимодействие: $(echo "$NETWORK_INFO" | grep -q '"com.docker.network.bridge.enable_icc":"false"' && echo "ЗАПРЕЩЕНО ✓" || echo "РАЗРЕШЕНО")"
else
    echo -e "${YELLOW}⚠ Сеть $NETWORK_NAME не найдена${NC}"
    echo "    Создайте: docker network create --driver bridge --subnet=172.20.0.0/16 --gateway=172.20.0.1 --opt com.docker.network.bridge.enable_icc=false $NETWORK_NAME"
fi
echo ""

# 4. Проверка образа
echo -e "${GREEN}=== 4. Проверка Docker образа ===${NC}"
if docker image inspect "$IMAGE" &> /dev/null; then
    echo -e "${GREEN}✓ Образ $IMAGE найден${NC}"
    echo "  Размер: $(docker image inspect "$IMAGE" --format='{{.Size}}' | numfmt --to=iec 2>/dev/null || echo 'неизвестно')"
    echo "  Создан: $(docker image inspect "$IMAGE" --format='{{.Created}}' | cut -dT -f1)"

    # Проверка слоёв образа
    LAYERS=$(docker history -q "$IMAGE" 2>/dev/null | wc -l)
    echo "  Количество слоёв: $LAYERS"
else
    echo -e "${RED}✗ Образ $IMAGE не найден!${NC}"
    echo "    Соберите: cd $DOCKER_DIR && docker build -t $IMAGE ."
fi
echo ""

# 5. Проверка GPU и аппаратного ускорения
echo -e "${GREEN}=== 5. Проверка GPU и аппаратного ускорения ===${NC}"

# Проверка NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓ NVIDIA GPU обнаружена:${NC}"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null | sed 's/^/    /'

    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
    echo "    Версия драйвера: $DRIVER_VERSION"

    # Проверка CUDA
    if command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $6}' | tr -d ',')
        echo "    CUDA версия: $CUDA_VERSION"
    fi
else
    echo -e "${YELLOW}⚠ NVIDIA GPU не обнаружена или драйвер не установлен${NC}"
    echo "    Установка: sudo dnf install akmod-nvidia"
fi

# Проверка устройств DRI (для Intel/AMD)
if [ -e /dev/dri ]; then
    echo -e "${GREEN}✓ Устройства DRI найдены:${NC}"
    ls -la /dev/dri/ 2>/dev/null | grep -E "card|render" | sed 's/^/    /'
else
    echo -e "${YELLOW}⚠ Устройства DRI не найдены${NC}"
fi

# Определение типа GPU через lspci
if command -v lspci &> /dev/null; then
    echo "Видеокарта по lspci:"
    lspci | grep -E "VGA|3D" | sed 's/^/    /'
fi

# Проверка драйверов OpenGL на хосте
if command -v glxinfo &> /dev/null; then
    echo "OpenGL информация на хосте:"
    GL_RENDERER=$(glxinfo -display "${DISPLAY:-:0}" 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
    GL_VERSION=$(glxinfo -display "${DISPLAY:-:0}" 2>/dev/null | grep "OpenGL version" | cut -d: -f2 | xargs)
    GL_VENDOR=$(glxinfo -display "${DISPLAY:-:0}" 2>/dev/null | grep "OpenGL vendor" | cut -d: -f2 | xargs)
    echo "    Рендерер: ${GL_RENDERER:-не доступен}"
    echo "    Версия: ${GL_VERSION:-не доступна}"
    echo "    Вендор: ${GL_VENDOR:-не доступен}"

    if echo "$GL_RENDERER" | grep -qi "llvmpipe"; then
        echo -e "    ${RED}✗ ВНИМАНИЕ: Используется программный рендеринг (llvmpipe)${NC}"
        echo "      Установите драйверы для вашего GPU"
    elif echo "$GL_RENDERER" | grep -qi "nvidia"; then
        echo -e "    ${GREEN}✓ Аппаратное ускорение NVIDIA активно${NC}"
    elif [ -n "$GL_RENDERER" ]; then
        echo -e "    ${GREEN}✓ Аппаратное ускорение активно${NC}"
    fi
else
    echo -e "${YELLOW}⚠ glxinfo не установлен${NC}"
    echo "    Установка: sudo dnf install mesa-demos"
fi

# Проверка NVIDIA Container Toolkit runtime
if command -v nvidia-smi &> /dev/null; then
    echo ""
    echo "Проверка NVIDIA Container Toolkit:"
    if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        echo -e "  ${GREEN}✓ NVIDIA Container Toolkit работает корректно${NC}"
    else
        echo -e "  ${RED}✗ NVIDIA Container Toolkit не работает${NC}"
        echo "    Проверьте установку: sudo dnf install nvidia-container-toolkit"
        echo "    Настройка: sudo nvidia-ctk runtime configure --runtime=docker"
        echo "    Перезапуск: sudo systemctl restart docker"
    fi
fi
echo ""

# 6. Проверка GPU внутри контейнера
echo -e "${GREEN}=== 6. Проверка GPU внутри Docker контейнера ===${NC}"
if docker image inspect "$IMAGE" &> /dev/null; then
    echo "Проверка доступа к GPU из контейнера:"

    # Проверка NVIDIA GPU из контейнера
    if command -v nvidia-smi &> /dev/null; then
        echo "  NVIDIA GPU из контейнера:"
        docker run --rm --gpus all --entrypoint bash "$IMAGE" -c "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null" 2>/dev/null | sed 's/^/    /' || echo "    NVIDIA GPU не доступна"
    fi

    # Проверка OpenGL внутри контейнера
    echo "  OpenGL библиотеки в контейнере:"
    docker run --rm --entrypoint bash "$IMAGE" -c "ldd /usr/bin/max 2>/dev/null | grep -E 'libGL|libEGL'" 2>/dev/null | sed 's/^/    /' || echo "    OpenGL библиотеки не найдены"
else
    echo "Образ не доступен для проверки"
fi
echo ""

# 7. Проверка изоляции контейнера (если запущен)
echo -e "${GREEN}=== 7. Проверка изоляции контейнера ===${NC}"
if docker ps -q -f name=^/${CONTAINER_NAME}$ &> /dev/null; then
    echo -e "${GREEN}✓ Контейнер $CONTAINER_NAME запущен${NC}"

    # Проверка капабилити
    echo "  Капабилити:"
    docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -A 5 "CapAdd\|CapDrop" | sed 's/^/    /'

    # Проверка доступа к /proc
    echo "  Доступ к /proc:"
    docker exec "$CONTAINER_NAME" ls /proc 2>&1 | head -3 | sed 's/^/    /' || echo "    Доступ запрещён"

    # Проверка доступа к /sys
    echo "  Доступ к /sys:"
    docker exec "$CONTAINER_NAME" ls /sys 2>&1 | head -3 | sed 's/^/    /' || echo "    Доступ запрещён"

    # Проверка сетевой изоляции
    echo "  Сетевые интерфейсы:"
    docker exec "$CONTAINER_NAME" ip addr show 2>/dev/null | grep -E "inet|eth" | sed 's/^/    /' || echo "    Сеть изолирована"

    # Проверка read-only root
    echo "  Root ФС:"
    docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -i "ReadonlyRootfs" | sed 's/^/    /'

    # Проверка AppArmor
    echo "  AppArmor профиль:"
    docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -i "apparmor" | sed 's/^/    /'

    # Проверка Seccomp
    echo "  Seccomp профиль:"
    docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -i "seccomp" | sed 's/^/    /'
else
    echo -e "${YELLOW}⚠ Контейнер $CONTAINER_NAME не запущен${NC}"
fi
echo ""

# 8. Проверка coredump
echo -e "${GREEN}=== 8. Последние coredump'ы ===${NC}"
if command -v journalctl &> /dev/null; then
    COREDUMP_COUNT=$(sudo journalctl -t systemd-coredump --since "1 hour ago" --no-pager 2>/dev/null | grep -c "Process.*max" || echo "0")
    if [ "$COREDUMP_COUNT" -gt 0 ]; then
        echo -e "${RED}Найдено $COREDUMP_COUNT coredump'ов за последний час:${NC}"
        sudo journalctl -t systemd-coredump --since "1 hour ago" --no-pager 2>/dev/null | grep -E "Process.*max|Signal|Timestamp" | head -10 | sed 's/^/  /'
    else
        echo "Coredump'ов не найдено"
    fi
else
    echo "journalctl не доступен (не systemd)"
fi
echo ""

# 9. Проверка конфигурации MAX
echo -e "${GREEN}=== 9. Конфигурация MAX ===${NC}"
if [ -d "$CONFIG_DIR" ]; then
    echo "Директория: $CONFIG_DIR"
    echo "Размер: $(du -sh "$CONFIG_DIR" 2>/dev/null | cut -f1)"
    echo "Файлы блокировки:"
    find "$CONFIG_DIR" -name "*Singleton*" -o -name "*.lock" 2>/dev/null | while read -r f; do
        echo "    - $(basename "$f")"
    done
else
    echo "Директория конфигурации не существует"
fi
echo ""

# 10. Проверка логов
echo -e "${GREEN}=== 10. Последние логи запуска ===${NC}"
if [ -d "$LOG_DIR" ] && [ "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
    LATEST_LOG=$(ls -t "$LOG_DIR"/console_*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG" ]; then
        echo "Последний лог: $(basename "$LATEST_LOG")"
        echo ""
        echo "Последние 20 строк:"
        echo "────────────────────────────────────────"
        tail -20 "$LATEST_LOG" 2>/dev/null | sed 's/^/    /'
        echo "────────────────────────────────────────"
    fi
else
    echo "Логи не найдены"
fi
echo ""

# 11. Проверка зависимостей внутри контейнера
echo -e "${GREEN}=== 11. Проверка зависимостей внутри контейнера ===${NC}"
if docker image inspect "$IMAGE" &> /dev/null; then
    echo "Проверка библиотек max:"
    MISSING_LIBS=$(docker run --rm --entrypoint bash "$IMAGE" -c "ldd /usr/bin/max 2>/dev/null | grep 'not found'" 2>/dev/null)
    if [ -n "$MISSING_LIBS" ]; then
        echo -e "${RED}  Отсутствуют библиотеки:${NC}"
        echo "$MISSING_LIBS" | sed 's/^/    /'
    else
        echo -e "  ${GREEN}Все библиотеки найдены${NC}"
    fi
else
    echo "Образ не доступен для проверки"
fi
echo ""

# 12. Интерактивная диагностика
echo -e "${GREEN}=== 12. Интерактивная диагностика ===${NC}"
echo "Выберите действие:"
echo "  1) Запустить оболочку внутри контейнера"
echo "  2) Запустить max с выводом всех логов"
echo "  3) Проверить версию glibc"
echo "  4) Проверить GPU внутри контейнера (glxinfo)"
echo "  5) Проверить переменные окружения GPU"
echo "  6) Проверить NVIDIA GPU (nvidia-smi)"
echo "  7) Проверить изоляцию контейнера (если запущен)"
echo "  8) Выйти"
echo ""
read -p "Ваш выбор [1-8]: " choice

case $choice in
    1)
        echo -e "${BLUE}Запуск оболочки...${NC}"
        echo "Команды для диагностики внутри:"
        echo "  ldd /usr/bin/max"
        echo "  /usr/bin/max --no-sandbox"
        echo "  nvidia-smi (если NVIDIA)"
        echo "  glxinfo | grep OpenGL"
        echo "  exit - для выхода"
        echo ""
        docker run --rm -it \
            --entrypoint bash \
            -e DISPLAY="$DISPLAY" \
            -e LIBGL_ALWAYS_SOFTWARE=0 \
            -e MESA_GL_VERSION_OVERRIDE=4.5 \
            -e __GLX_VENDOR_LIBRARY_NAME=nvidia \
            -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
            --gpus all \
            --net=host \
            "$IMAGE"
        ;;
    2)
        echo -e "${BLUE}Запуск max с выводом логов...${NC}"
        docker run --rm -it \
            -e DISPLAY="$DISPLAY" \
            -e QT_QPA_PLATFORM=xcb \
            -e LIBGL_ALWAYS_SOFTWARE=0 \
            -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
            --gpus all \
            --net=host \
            --entrypoint bash \
            "$IMAGE" \
            -c "/usr/bin/max --no-sandbox 2>&1 | tee /tmp/max_debug.log"
        ;;
    3)
        echo -e "${BLUE}Версия glibc в контейнере:${NC}"
        docker run --rm --entrypoint bash "$IMAGE" -c "ldd --version | head -1"
        echo ""
        echo -e "${BLUE}Версия glibc на хосте:${NC}"
        ldd --version | head -1
        ;;
    4)
        echo -e "${BLUE}Проверка GPU внутри контейнера...${NC}"
        docker run --rm \
            --entrypoint bash \
            --gpus all \
            "$IMAGE" \
            -c "glxinfo 2>/dev/null | grep -E 'OpenGL (renderer|version)' || echo 'glxinfo не установлен'"
        ;;
    5)
        echo -e "${BLUE}Переменные окружения для GPU:${NC}"
        echo "  LIBGL_ALWAYS_SOFTWARE=0"
        echo "  MESA_GL_VERSION_OVERRIDE=4.5"
        echo "  MESA_GLES_VERSION_OVERRIDE=3.2"
        echo "  __GL_SYNC_TO_VBLANK=0"
        echo "  __GL_SHADER_DISK_CACHE=1"
        echo "  vblank_mode=0"
        echo "  NVIDIA_VISIBLE_DEVICES=all"
        echo "  NVIDIA_DRIVER_CAPABILITIES=all"
        echo "  __GLX_VENDOR_LIBRARY_NAME=nvidia"
        echo ""
        echo -e "${BLUE}Текущие переменные:${NC}"
        env | grep -E "LIBGL|MESA|__GL|vblank|NVIDIA" | sed 's/^/    /' || echo "    Не установлены"
        ;;
    6)
        echo -e "${BLUE}Проверка NVIDIA GPU...${NC}"
        if command -v nvidia-smi &> /dev/null; then
            echo "На хосте:"
            nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total --format=csv | sed 's/^/    /'
            echo ""
            echo "В контейнере:"
            docker run --rm --gpus all --entrypoint bash "$IMAGE" -c "nvidia-smi 2>/dev/null || echo 'nvidia-smi не доступен'" | sed 's/^/    /'
        else
            echo -e "${RED}NVIDIA драйверы не установлены на хосте${NC}"
        fi
        ;;
    7)
        echo -e "${BLUE}Проверка изоляции контейнера...${NC}"
        if docker ps -q -f name=^/${CONTAINER_NAME}$ &> /dev/null; then
            echo "  Капабилити:"
            docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -A 5 "CapAdd\|CapDrop" | sed 's/^/    /'
            echo ""
            echo "  Seccomp профиль:"
            docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -i "seccomp" | sed 's/^/    /'
            echo ""
            echo "  AppArmor профиль:"
            docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -i "apparmor" | sed 's/^/    /'
            echo ""
            echo "  Read-only root:"
            docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -i "ReadonlyRootfs" | sed 's/^/    /'
        else
            echo -e "${YELLOW}Контейнер $CONTAINER_NAME не запущен${NC}"
        fi
        ;;
    8)
        echo "Выход"
        ;;
    *)
        echo "Неверный выбор"
        ;;
esac

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Диагностика завершена${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
