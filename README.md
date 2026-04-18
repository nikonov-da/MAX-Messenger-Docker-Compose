# 🔒 Полная инструкция: MAX Messenger в Docker с изоляцией и аппаратным ускорением

## 📋 Содержание

1. [Требования к системе](#требования-к-системе)
2. [Установка Docker и Docker Compose](#установка-docker-и-docker-compose)
3. [Установка NVIDIA Container Toolkit](#установка-nvidia-container-toolkit)
4. [Структура проекта](#структура-проекта)
5. [Создание Dockerfile](#создание-dockerfile)
6. [Создание скриптов с изоляцией](#создание-скриптов-с-изоляцией)
7. [Docker Compose](#docker-compose)
8. [Настройка безопасности](#настройка-безопасности)
9. [Сборка образа](#сборка-образа)
10. [Запуск и управление](#запуск-и-управление)
11. [Создание десктопных ярлыков](#создание-десктопных-ярлыков)
12. [Диагностика и отладка](#диагностика-и-отладка)
13. [Устранение неполадок](#устранение-неполадок)

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

# 2. Установка зависимостей
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
│   ├── seccomp-max.json          # Seccomp профиль безопасности
│   ├── install-apparmor-profile.sh # Установка AppArmor
│   ├── security-check.sh         # Проверка изоляции
│   └── setup-isolated-network.sh # Создание изолированной сети
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

Создайте `~/max-messenger/bin/start-max.sh` (содержимое предоставлено выше).

### 2. Seccomp профиль `seccomp-max.json`

Создайте `~/max-messenger/bin/seccomp-max.json` (содержимое предоставлено выше).

### 3. Скрипт установки AppArmor `install-apparmor-profile.sh`

Создайте `~/max-messenger/bin/install-apparmor-profile.sh` (содержимое предоставлено выше).

### 4. Скрипт проверки безопасности `security-check.sh`

Создайте `~/max-messenger/bin/security-check.sh` (содержимое предоставлено выше).

### 5. Скрипт создания сети `setup-isolated-network.sh`

Создайте `~/max-messenger/bin/setup-isolated-network.sh` (содержимое предоставлено выше).

### 6. Скрипт диагностики `max-debug.sh`

Создайте `~/max-messenger/bin/max-debug.sh` (содержимое предоставлено выше).

### 7. Скрипт восстановления `fix-after-reboot.sh`

Создайте `~/max-messenger/bin/fix-after-reboot.sh` (содержимое предоставлено выше).

### 8. Установка прав

```bash
chmod +x ~/max-messenger/bin/*.sh
```

---

## Docker Compose

### Что такое Docker Compose и зачем он нужен

Docker Compose позволяет управлять многоконтейнерными приложениями одной командой. Для MAX Messenger он нужен чтобы:

1. **Упростить запуск** - одна команда вместо длинной `docker run` с кучей параметров
2. **Автоматизировать настройку** - все параметры (сеть, тома, переменные) в одном файле
3. **Легко переиспользовать** - не нужно помнить сложные флаги командной строки
4. **Версионировать конфигурацию** - файл можно хранить в Git

### Создание `docker-compose.yml`

Создайте файл `~/max-messenger/docker-compose.yml`:

```yaml
version: '3.8'

# Изолированная сеть
networks:
  max_isolated_network:
    external: true
    name: max_isolated_network

services:
  max-messenger:
    image: max-messenger:latest
    container_name: max_messenger
    
    # Сеть с фиксированным IP
    networks:
      max_isolated_network:
        ipv4_address: 172.20.0.100
    
    # Безопасность - запрет новых привилегий
    security_opt:
      - no-new-privileges:true
      - seccomp:./bin/seccomp-max.json
      - apparmor:docker-max-messenger
      - label:disable
    
    # Капабилити (только необходимые)
    cap_add:
      - NET_ADMIN
      - NET_RAW
    cap_drop:
      - ALL
    
    # Read-only корневая ФС
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=128M
      - /run:rw,noexec,nosuid,size=64M
      - /home/maxuser/.config/max:rw,noexec,nosuid,size=256M
    
    # Переменные окружения
    environment:
      - DISPLAY=${DISPLAY:-:0}
      - QT_QPA_PLATFORM=xcb
      - QT_X11_NO_MITSHM=1
      - LIBGL_ALWAYS_SOFTWARE=0
      - ELECTRON_NO_SANDBOX=1
      - SECRETS_SERVICE_IGNORE=1
      - NO_AT_BRIDGE=1
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
    
    # Тома (монтирование)
    volumes:
      - /tmp/.X11-unix/X0:/tmp/.X11-unix/X0:ro
      - ${HOME}/.max:/home/maxuser/.config/max:rw
      - ./logs:/home/maxuser/logs:rw
    
    # Проброс GPU
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    
    # Политики
    restart: "no"
    stop_signal: SIGTERM
    stop_grace_period: 10s
    stdin_open: false
    tty: false
```

### Скрипт для запуска через Docker Compose

Создайте `~/max-messenger/run-compose.sh`:

```bash
#!/usr/bin/env bash

cd "$(dirname "$0")"

case "$1" in
    up)
        echo "🚀 Запуск MAX Messenger через Docker Compose..."
        docker compose up
        ;;
    up-d)
        echo "🚀 Запуск MAX Messenger в фоне..."
        docker compose up -d
        ;;
    down)
        echo "🛑 Остановка MAX Messenger..."
        docker compose down
        ;;
    restart)
        echo "🔄 Перезапуск MAX Messenger..."
        docker compose restart
        ;;
    logs)
        echo "📋 Логи MAX Messenger..."
        docker compose logs -f
        ;;
    build)
        echo "🔨 Сборка образа..."
        cd docker
        docker build --no-cache -t max-messenger:latest .
        cd ..
        ;;
    status)
        docker compose ps
        ;;
    exec)
        echo "💻 Вход в контейнер..."
        docker compose exec max-messenger bash
        ;;
    *)
        echo "Использование: $0 {up|up-d|down|restart|logs|build|status|exec}"
        echo ""
        echo "Команды:"
        echo "  up      - Запуск с выводом логов"
        echo "  up-d    - Запуск в фоновом режиме"
        echo "  down    - Остановка"
        echo "  restart - Перезапуск"
        echo "  logs    - Просмотр логов"
        echo "  build   - Пересборка образа"
        echo "  status  - Статус контейнера"
        echo "  exec    - Вход в контейнер"
        exit 1
        ;;
esac
```

```bash
chmod +x ~/max-messenger/run-compose.sh
```

### Сравнение: Docker run vs Docker Compose

| Аспект | Docker run | Docker Compose |
|--------|-----------|----------------|
| Длина команды | ~20 параметров | 2 слова |
| Запоминание параметров | Нужно помнить или копировать | Всё в файле |
| Версионирование | Нет | Есть (в Git) |
| Переиспользование | Копировать команду | Просто `up` |
| Ошибки | Легко ошибиться | Автоматически проверяет |

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

### Через Docker

```bash
cd ~/max-messenger/docker
docker build --no-cache -t max-messenger:latest .
```

### Через Docker Compose

```bash
cd ~/max-messenger
./run-compose.sh build
```

---

## Запуск и управление

### Запуск через скрипт

```bash
~/max-messenger/bin/start-max.sh
```

### Запуск через Docker Compose

```bash
cd ~/max-messenger

# Запуск с выводом логов
./run-compose.sh up

# Запуск в фоне
./run-compose.sh up-d

# Просмотр статуса
./run-compose.sh status

# Просмотр логов
./run-compose.sh logs

# Остановка
./run-compose.sh down

# Перезапуск
./run-compose.sh restart

# Вход в контейнер (для отладки)
./run-compose.sh exec
```

### Остановка

```bash
docker stop max_messenger
# или
./run-compose.sh down
```

### Просмотр логов

```bash
tail -f ~/max-messenger/logs/console_*.log
# или
./run-compose.sh logs
```

---

## Создание десктопных ярлыков

### Скрипт `create-desktop-entries.sh`

```bash
#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$DESKTOP_DIR"

ICON_MAIN="$SCRIPT_DIR/MAX-1024x1024.png"
ICON_DEBUG="$SCRIPT_DIR/MAX-DEBUG-TOOL.png"
ICON_FIX="$SCRIPT_DIR/MAX-FIX-TOOL.png"

[ ! -f "$ICON_MAIN" ] && ICON_MAIN=""
[ ! -f "$ICON_DEBUG" ] && ICON_DEBUG=""
[ ! -f "$ICON_FIX" ] && ICON_FIX=""

# MAX Messenger (через скрипт)
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

# MAX Messenger (через Docker Compose) - альтернатива
cat > "$DESKTOP_DIR/max-messenger-compose.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Messenger (Compose)
GenericName=Messenger
Comment=Запуск мессенджера MAX через Docker Compose
Exec=${PROJECT_DIR}/run-compose.sh up
Icon=${ICON_MAIN:-utilities-terminal}
Terminal=true
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
echo "  - MAX Messenger (Compose)"
echo "  - MAX Debug Tool"
echo "  - MAX Fix Tool"
echo "  - MAX Security Check"
```

### Установка ярлыков

```bash
~/max-messenger/bin/create-desktop-entries.sh
```

После этого в меню приложений появятся:
- **MAX Messenger** - основной запуск
- **MAX Messenger (Compose)** - запуск через Docker Compose
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

### Проверка через Docker Compose

```bash
cd ~/max-messenger
./run-compose.sh status
./run-compose.sh logs
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
| Docker Compose не найден | Установите: `sudo apt install docker-compose-plugin` |

---

## Заключение

После выполнения всех шагов вы получите:

- ✅ **Полностью изолированное окружение** (сеть, ФС, капабилити)
- ✅ **Seccomp и AppArmor профили безопасности**
- ✅ **Аппаратное ускорение NVIDIA GPU**
- ✅ **Docker Compose для удобного управления**
- ✅ **Пять десктопных ярлыков** для всех операций
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

# Запуск мессенджера (скрипт)
~/max-messenger/bin/start-max.sh

# Или через Docker Compose
cd ~/max-messenger && ./run-compose.sh up

# Проверка безопасности
~/max-messenger/bin/security-check.sh
```

**Ваш MAX Messenger теперь работает в полностью изолированном окружении с аппаратным ускорением!** 🔒🚀
