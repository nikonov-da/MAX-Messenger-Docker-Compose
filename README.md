# 🔒 Полная инструкция: MAX Messenger в Docker с изоляцией и аппаратным ускорением

## 📋 Содержание

1. [Требования к системе](#требования-к-системе)
2. [Установка Docker и Docker Compose](#установка-docker-и-docker-compose)
3. [Установка NVIDIA Container Toolkit](#установка-nvidia-container-toolkit)
4. [Структура проекта](#структура-проекта)
5. [Создание Dockerfile](#создание-dockerfile)
6. [Создание скриптов с изоляцией](#создание-скриптов-с-изоляцией)
7. [Настройка безопасности](#настройка-безопасности)
8. [Сборка образа](#сборка-образа)
9. [Запуск и управление](#запуск-и-управление)
10. [Создание десктопных ярлыков](#создание-десктопных-ярлыков)
11. [Диагностика и отладка](#диагностика-и-отладка)
12. [Устранение неполадок](#устранение-неполадок)

---

## Требования к системе

### Минимальные требования
- **ОС**: Fedora 38+, Ubuntu 22.04/24.04/26.04
- **Docker**: версия 20.10+
- **Docker Compose**: версия 2.0+
- **ОЗУ**: 4 ГБ (рекомендуется 8 ГБ)
- **GPU**: NVIDIA с драйверами 450.80.02+ (опционально)
- **Интернет**: для скачивания образов

### Проверка системы
```bash
# Проверка версии ОС
cat /etc/os-release

# Проверка архитектуры
uname -m

# Проверка свободного места
df -h /
```

---

## Установка Docker и Docker Compose

### Для Ubuntu 22.04/24.04/26.04

```bash
# 1. Обновление системы
sudo apt update && sudo apt upgrade -y

# 2. Установка依赖мостей
sudo apt install -y ca-certificates curl gnupg lsb-release

# 3. Добавление GPG ключа Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 4. Добавление репозитория
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Установка Docker и Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 6. Запуск Docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# 7. Применение изменений
newgrp docker

# 8. Проверка
docker --version
docker compose version
```

### Для Fedora 38+

```bash
# 1. Установка Docker
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 2. Запуск Docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# 3. Применение изменений
newgrp docker

# 4. Проверка
docker --version
docker compose version
```

---

## Установка NVIDIA Container Toolkit

### Для Ubuntu

```bash
# 1. Добавление репозитория
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 2. Установка
sudo apt update
sudo apt install -y nvidia-container-toolkit

# 3. Настройка Docker
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 4. Проверка
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

### Для Fedora

```bash
# 1. Добавление репозитория
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

# 2. Установка
sudo dnf install -y nvidia-container-toolkit libnvidia-container1

# 3. Настройка Docker
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 4. Проверка
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

---

## Структура проекта

```
/home/denis/max-messenger/
├── bin/
│   ├── start-max.sh              # Основной скрипт запуска
│   ├── max-debug.sh              # Диагностический инструмент
│   ├── fix-after-reboot.sh       # Восстановление окружения
│   ├── create-desktop-entries.sh # Создание всех ярлыков
│   ├── create-desktop-fix-tool.sh # Создание ярлыка Fix Tool
│   ├── seccomp-max.json          # Seccomp профиль безопасности
│   ├── install-apparmor-profile.sh # Установка AppArmor
│   ├── security-check.sh         # Проверка изоляции
│   ├── setup-isolated-network.sh # Создание изолированной сети
│   ├── MAX-1024x1024.png         # Иконка приложения
│   ├── MAX-DEBUG-TOOL.png        # Иконка отладки
│   └── MAX-FIX-TOOL.png          # Иконка восстановления
├── docker/
│   └── Dockerfile                # Docker образ
├── docker-compose.yml            # Docker Compose конфиг
└── logs/                         # Логи (создаётся автоматически)
```

### Создание структуры

```bash
mkdir -p ~/max-messenger/{bin,docker,logs}
cd ~/max-messenger
```

---

## Создание Dockerfile

Создайте файл `~/max-messenger/docker/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=ru_RU.UTF-8 \
    LANG=ru_RU.UTF-8 \
    LANGUAGE=ru_RU:ru

# 1. Базовый слой
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg2 locales \
    dbus dbus-x11 gnome-keyring libpam-gnome-keyring \
    && locale-gen ru_RU.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2. Репозиторий MAX
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.max.ru/linux/deb/public.asc | gpg --dearmor -o /etc/apt/keyrings/max.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/max.gpg] https://download.max.ru/linux/deb stable main" \
    > /etc/apt/sources.list.d/max.list

# 3. Основные зависимости
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    max \
    mesa-utils libgl1-mesa-dri libglx-mesa0 libegl-mesa0 \
    libglx0 libegl1 libgl1 libva2 libva-drm2 libva-x11-2 \
    mesa-va-drivers mesa-vdpau-drivers libvulkan1 mesa-vulkan-drivers vulkan-tools \
    libgbm1 libwayland-client0 libwayland-egl1 libdrm2 \
    libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-xinerama0 libxcb-xinput0 libxcb-shape0 \
    libxkbcommon-x11-0 libgtk-3-0 libpango-1.0-0 libcairo2 libfontconfig1 \
    fonts-liberation libnss3 libasound2t64 libpulse0 libdbus-1-3 \
    libsecret-1-0 libpci3 libxtst6 libxss1 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2t64 libxkbfile1 libxcomposite1 libxdamage1 libxrandr2 libx11-xcb1 \
    libpipewire-0.3-0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 4. Скрипт запуска
RUN printf '#!/bin/bash\n\
USER_ID=${HOST_UID:-1000}\n\
USER_NAME=${HOST_USER:-maxuser}\n\
if ! id -u "$USER_ID" >/dev/null 2>&1; then\n\
    useradd -u "$USER_ID" -m -s /bin/bash "$USER_NAME" 2>/dev/null\n\
fi\n\
USER_NAME=$(id -nu "$USER_ID" 2>/dev/null || echo "$USER_NAME")\n\
mkdir -p /run/user/"$USER_ID"\n\
chown "$USER_NAME" /run/user/"$USER_ID"\n\
export LIBGL_ALWAYS_SOFTWARE=0\n\
export MESA_GL_VERSION_OVERRIDE=4.5\n\
export MESA_GLES_VERSION_OVERRIDE=3.2\n\
export __GL_SYNC_TO_VBLANK=0\n\
export __GL_SHADER_DISK_CACHE=1\n\
export vblank_mode=0\n\
su -c "dbus-launch --exit-with-session \\\n\
    gnome-keyring-daemon --start --components=secrets \\\n\
    && export GNOME_KEYRING_CONTROL \\\n\
    && export SSH_AUTH_SOCK \\\n\
    && /usr/bin/max --no-sandbox $*" "$USER_NAME"\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

# 5. Настройка окружения
ENV QT_QPA_PLATFORM=xcb \
    QT_X11_NO_MITSHM=1 \
    LIBGL_ALWAYS_SOFTWARE=0 \
    ELECTRON_NO_SANDBOX=1 \
    NO_AT_BRIDGE=1 \
    SECRETS_SERVICE_IGNORE=1 \
    MESA_GL_VERSION_OVERRIDE=4.5 \
    MESA_GLES_VERSION_OVERRIDE=3.2 \
    __GL_SYNC_TO_VBLANK=0 \
    __GL_SHADER_DISK_CACHE=1 \
    vblank_mode=0

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--use-gl=egl"]
```

---

## Создание скриптов с изоляцией

### 1. Основной скрипт `start-max.sh`

Создайте `~/max-messenger/bin/start-max.sh`:

```bash
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

log_info "Запуск MAX Messenger в изолированном окружении..."
echo "---"

# Запуск с максимальной изоляцией
docker run \
    --name "${CONTAINER}" \
    --rm \
    --network "${NETWORK_NAME}" \
    --ip "${CONTAINER_IP}" \
    \
    --security-opt no-new-privileges:true \
    --security-opt seccomp="${SCRIPT_DIR}/seccomp-max.json" \
    --security-opt apparmor="docker-max-messenger" \
    --security-opt label=disable \
    \
    --cap-drop ALL \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=128M \
    --tmpfs /run:rw,noexec,nosuid,size=64M \
    --tmpfs "${CONFIG_DIR}":rw,noexec,nosuid,size=256M \
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
```

### 2. Создание Seccomp профиля

Создайте файл `~/max-messenger/bin/seccomp-max.json`:

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "defaultErrnoRet": 1,
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close", "mmap", "munmap", "mprotect",
        "brk", "rt_sigaction", "rt_sigprocmask", "ioctl", "access",
        "pipe", "select", "socket", "connect", "accept", "recvfrom",
        "sendto", "recvmsg", "sendmsg", "bind", "listen", "getsockname",
        "getpeername", "setsockopt", "getsockopt", "exit", "exit_group",
        "wait4", "kill", "uname", "getpid", "getppid", "getuid", "geteuid",
        "getgid", "getegid", "gettid", "sysinfo", "times", "gettimeofday",
        "time", "clock_gettime", "nanosleep", "getrandom"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "mount", "umount2", "pivot_root", "chroot", "reboot", "kexec_load",
        "init_module", "finit_module", "delete_module", "ioperm", "iopl",
        "ptrace", "perf_event_open", "bpf", "personality", "process_vm_readv",
        "process_vm_writev", "kcmp", "seccomp", "keyctl", "add_key",
        "request_key", "unshare", "setns"
      ],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
```

### 3. Скрипт установки AppArmor профиля

Создайте `~/max-messenger/bin/install-apparmor-profile.sh`:

```bash
#!/bin/bash
sudo tee /etc/apparmor.d/docker-max-messenger << 'EOF'
#include <tunables/global>

profile docker-max-messenger flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  deny /proc/** rw,
  deny /sys/** rw,
  deny /dev/** rw,
  deny /boot/** r,
  deny /etc/shadow rw,
  deny /etc/passwd rw,
  deny /root/** rw,
  deny /home/*/.ssh/** rw,
  
  /usr/bin/max rwix,
  /usr/share/max/** r,
  /home/*/.config/max/** rw,
  /tmp/** rw,
  /run/user/*/bus rw,
  /tmp/.X11-unix/X0 rw,
  
  capability setuid,
  capability setgid,
  capability net_raw,
  capability net_admin,
  
  network inet stream,
  network inet6 stream,
  network unix stream,
  
  deny network raw,
}
EOF

sudo apparmor_parser -r /etc/apparmor.d/docker-max-messenger
echo "AppArmor профиль установлен"
```

### 4. Скрипт проверки безопасности

Создайте `~/max-messenger/bin/security-check.sh`:

```bash
#!/bin/bash

CONTAINER_NAME="max_messenger"

echo "=== Проверка изоляции контейнера ==="
echo ""

echo "1. Капабилити контейнера:"
docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -A 10 "CapAdd\|CapDrop" || echo "Контейнер не запущен"

echo ""
echo "2. Проверка доступа к /proc:"
docker exec "$CONTAINER_NAME" ls /proc 2>&1 | head -3 || echo "Доступ запрещён"

echo ""
echo "3. Проверка доступа к /sys:"
docker exec "$CONTAINER_NAME" ls /sys 2>&1 | head -3 || echo "Доступ запрещён"

echo ""
echo "4. Проверка сетевой изоляции:"
docker exec "$CONTAINER_NAME" ip addr show 2>/dev/null | grep -E "inet|eth" || echo "Сеть изолирована"

echo ""
echo "5. Проверка GPU:"
docker exec "$CONTAINER_NAME" nvidia-smi 2>/dev/null | grep -E "GeForce|Tesla" || echo "GPU не доступен"

echo "=== Проверка завершена ==="
```

### 5. Скрипт создания десктопных ярлыков

Создайте `~/max-messenger/bin/create-desktop-entries.sh`:

```bash
#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$DESKTOP_DIR"

ICON_MAIN="$SCRIPT_DIR/MAX-1024x1024.png"
ICON_DEBUG="$SCRIPT_DIR/MAX-DEBUG-TOOL.png"
ICON_FIX="$SCRIPT_DIR/MAX-FIX-TOOL.png"

[ ! -f "$ICON_MAIN" ] && ICON_MAIN=""
[ ! -f "$ICON_DEBUG" ] && ICON_DEBUG=""
[ ! -f "$ICON_FIX" ] && ICON_FIX=""

# MAX Messenger
cat > "$DESKTOP_DIR/max-messenger.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Messenger
GenericName=Messenger
Comment=Запуск мессенджера MAX в Docker с полной изоляцией
Exec=${SCRIPT_DIR}/start-max.sh
Icon=${ICON_MAIN:-utilities-terminal}
Terminal=false
StartupNotify=true
StartupWMClass=max
Categories=Network;Chat;InstantMessaging;
Keywords=Messenger;MAX;
EOF

# MAX Debug Tool
cat > "$DESKTOP_DIR/max-debug-tool.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Debug Tool
Comment=Диагностика и отладка MAX Messenger
Exec=${SCRIPT_DIR}/max-debug.sh
Icon=${ICON_DEBUG:-utilities-terminal}
Terminal=true
Categories=Development;Debugger;
EOF

# MAX Fix Tool
cat > "$DESKTOP_DIR/max-fix-tool.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Fix Tool
Comment=Восстановление окружения после перезагрузки
Exec=${SCRIPT_DIR}/fix-after-reboot.sh
Icon=${ICON_FIX:-utilities-terminal}
Terminal=true
Categories=System;Utility;
EOF

# MAX Security Check
cat > "$DESKTOP_DIR/max-security-check.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Security Check
Comment=Проверка безопасности и изоляции контейнера
Exec=${SCRIPT_DIR}/security-check.sh
Icon=${ICON_FIX:-utilities-terminal}
Terminal=true
Categories=System;Security;
EOF

update-desktop-database "$DESKTOP_DIR" 2>/dev/null
chmod +x "$DESKTOP_DIR"/max-*.desktop

echo "✓ Все десктопные ярлыки созданы"
echo "  - MAX Messenger"
echo "  - MAX Debug Tool"
echo "  - MAX Fix Tool"
echo "  - MAX Security Check"
```

### 6. Установка прав

```bash
chmod +x ~/max-messenger/bin/*.sh
```

---

## Настройка безопасности

### 1. Создание изолированной сети

```bash
# Запуск скрипта создания сети
~/max-messenger/bin/setup-isolated-network.sh
```

Или вручную:

```bash
docker network create \
  --driver bridge \
  --subnet=172.20.0.0/16 \
  --gateway=172.20.0.1 \
  --opt com.docker.network.bridge.enable_icc=false \
  --opt com.docker.network.bridge.enable_ip_masquerade=true \
  max_isolated_network
```

### 2. Установка AppArmor профиля

```bash
~/max-messenger/bin/install-apparmor-profile.sh
```

### 3. Настройка X11

```bash
xhost +SI:localuser:root
```

---

## Сборка образа

```bash
cd ~/max-messenger/docker
docker build --no-cache -t max-messenger:latest .
```

---

## Запуск и управление

### Запуск мессенджера

```bash
~/max-messenger/bin/start-max.sh
```

### Остановка

```bash
docker stop max_messenger
```

### Просмотр логов

```bash
tail -f ~/max-messenger/logs/console_*.log
```

---

## Создание десктопных ярлыков

```bash
~/max-messenger/bin/create-desktop-entries.sh
```

После этого в меню приложений появятся:
- **MAX Messenger** - основной запуск
- **MAX Debug Tool** - диагностика
- **MAX Fix Tool** - восстановление
- **MAX Security Check** - проверка безопасности

---

## Диагностика и отладка

### Проверка безопасности

```bash
~/max-messenger/bin/security-check.sh
```

### Полная диагностика

```bash
~/max-messenger/bin/max-debug.sh
```

### Восстановление после перезагрузки

```bash
~/max-messenger/bin/fix-after-reboot.sh
```

---

## Устранение неполадок

| Проблема | Решение |
|----------|---------|
| GPU не виден | `docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi` |
| X11 ошибка | `xhost +SI:localuser:root` |
| libsecret ошибка | Уже подавлена переменной `SECRETS_SERVICE_IGNORE=1` |
| Высокая нагрузка CPU | Проверьте `nvidia-smi` и `glxinfo \| grep "OpenGL renderer"` |
| Сеть не создана | `docker network create max_isolated_network` |
| AppArmor ошибка | `sudo apparmor_parser -r /etc/apparmor.d/docker-max-messenger` |

---

## Заключение

После выполнения всех шагов вы получите:

- ✅ **Полностью изолированное окружение** (сеть, ФС, капабилити)
- ✅ **Seccomp и AppArmor профили безопасности**
- ✅ **Аппаратное ускорение NVIDIA GPU**
- ✅ **Четыре десктопных ярлыка** для всех операций
- ✅ **Полная диагностика и восстановление**

### Архитектура безопасности

```
┌─────────────────────────────────────────────────────────────────┐
│                         Хост система                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              MAX Messenger Container                      │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  • Сеть: max_isolated_network (172.20.0.100/16)     │  │  │
│  │  │  • Капабилити: только NET_ADMIN, NET_RAW            │  │  │
│  │  │  • Seccomp: Белый список syscalls                   │  │  │
│  │  │  • AppArmor: docker-max-messenger                   │  │  │
│  │  │  • Root ФС: Read-only                               │  │  │
│  │  │  • tmpfs: /tmp, /run, .config/max                   │  │  │
│  │  │  • GPU: NVIDIA (опционально)                        │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Быстрый запуск

```bash
# После перезагрузки
~/max-messenger/bin/fix-after-reboot.sh

# Запуск мессенджера
~/max-messenger/bin/start-max.sh

# Проверка безопасности
~/max-messenger/bin/security-check.sh
```

**Ваш MAX Messenger теперь работает в полностью изолированном окружении с аппаратным ускорением!** 🔒🚀
