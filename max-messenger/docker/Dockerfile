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

# 3. Основные зависимости (с добавленными библиотеками)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    max \
    # GPU ускорение
    mesa-utils libgl1-mesa-dri libglx-mesa0 libegl-mesa0 \
    libglx0 libegl1 libgl1 libva2 libva-drm2 libva-x11-2 \
    mesa-va-drivers mesa-vdpau-drivers libvulkan1 mesa-vulkan-drivers vulkan-tools \
    # Графика и Wayland
    libgbm1 libwayland-client0 libwayland-egl1 libdrm2 \
    # XCB библиотеки (добавлены все необходимые)
    libxcb-cursor0 \
    libxcb-cursor0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xinput0 \
    libxcb-shape0 \
    libxcb-util1 \
    libxcb-xkb1 \
    libxcb-randr0 \
    libxcb-xfixes0 \
    libxcb-sync1 \
    libxcb-shm0 \
    libxcb-glx0 \
    libxcb-present0 \
    libxcb-dri2-0 \
    libxcb-dri3-0 \
    libxcb-xf86dri0 \
    libxkbcommon-x11-0 \
    # GTK и интерфейс
    libgtk-3-0 libpango-1.0-0 libcairo2 libfontconfig1 \
    fonts-liberation fonts-noto-color-emoji \
    # Системные зависимости
    libnss3 libasound2t64 libpulse0 libdbus-1-3 \
    libsecret-1-0 libpci3 libxtst6 libxss1 libatk1.0-0 \
    libatk-bridge2.0-0 libcups2t64 libxkbfile1 libxcomposite1 \
    libxdamage1 libxrandr2 libx11-xcb1 libpipewire-0.3-0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 4. Скрипт запуска (исправлен для работы без su)
RUN printf '#!/bin/bash\n\
# Установка переменных окружения\n\
export LIBGL_ALWAYS_SOFTWARE=0\n\
export MESA_GL_VERSION_OVERRIDE=4.5\n\
export MESA_GLES_VERSION_OVERRIDE=3.2\n\
export __GL_SYNC_TO_VBLANK=0\n\
export __GL_SHADER_DISK_CACHE=1\n\
export vblank_mode=0\n\
export QT_QPA_PLATFORM=xcb\n\
export QT_X11_NO_MITSHM=1\n\
export ELECTRON_NO_SANDBOX=1\n\
export NO_AT_BRIDGE=1\n\
export SECRETS_SERVICE_IGNORE=1\n\
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-autolaunch:}\n\
\n\
# Создание директории runtime\n\
mkdir -p /run/user/$(id -u) 2>/dev/null\n\
\n\
# Запуск gnome-keyring\n\
gnome-keyring-daemon --start --components=secrets 2>/dev/null\n\
\n\
# Запуск приложения\n\
exec /usr/bin/max --no-sandbox "$@"\n\
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
