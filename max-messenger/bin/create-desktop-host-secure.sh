#!/usr/bin/env bash

# create-desktop-host-secure.sh - Создание десктопного ярлыка для MAX Messenger Host Secure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DESKTOP_DIR="$HOME/.local/share/applications"

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Создание директории для десктоп файлов
mkdir -p "$DESKTOP_DIR"

# Проверка наличия иконки
ICON_PATH="$SCRIPT_DIR/MAX-1024x1024.png"

if [ ! -f "$ICON_PATH" ]; then
    log_warning "Иконка MAX-1024x1024.png не найдена, будет использована стандартная"
    ICON_PATH=""
fi

# Проверка наличия скрипта запуска HOST SECURE
RUN_SCRIPT="$PROJECT_DIR/run-host-secure.sh"

if [ ! -f "$RUN_SCRIPT" ]; then
    log_error "Скрипт run-host-secure.sh не найден!"
    log_info "Создайте его в директории проекта: $PROJECT_DIR"
    exit 1
fi

# Создание десктоп файла для MAX Messenger Host Secure
log_info "Создание ярлыка для MAX Messenger (Host Secure режим)..."

cat > "$DESKTOP_DIR/max-messenger-host-secure.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Messenger (Host Secure)
GenericName=Messenger
Comment=Запуск мессенджера MAX в Docker с максимальной безопасностью (Host режим)
Exec=${RUN_SCRIPT}
Icon=${ICON_PATH:-utilities-terminal}
Terminal=true
StartupNotify=true
StartupWMClass=max
Categories=Network;Chat;InstantMessaging;
Keywords=Messenger;MAX;secure;host;
X-GNOME-Autostart-enabled=false
X-Desktop-File-Install-Version=0.26
EOF

# Проверка создания
if [ -f "$DESKTOP_DIR/max-messenger-host-secure.desktop" ]; then
    chmod +x "$DESKTOP_DIR/max-messenger-host-secure.desktop"
    log_success "Ярлык MAX Messenger (Host Secure) создан: $DESKTOP_DIR/max-messenger-host-secure.desktop"
else
    log_error "Не удалось создать ярлык MAX Messenger (Host Secure)"
    exit 1
fi

# Обновление базы десктоп файлов
log_info "Обновление базы десктоп файлов..."
update-desktop-database "$DESKTOP_DIR" 2>/dev/null

if [ $? -eq 0 ]; then
    log_success "База десктоп файлов обновлена"
else
    log_warning "Не удалось обновить базу (это не критично)"
fi

# Проверка валидности
if command -v desktop-file-validate &> /dev/null; then
    log_info "Проверка валидности десктоп файла..."
    if desktop-file-validate "$DESKTOP_DIR/max-messenger-host-secure.desktop" 2>/dev/null; then
        log_success "Файл max-messenger-host-secure.desktop валиден"
    else
        log_warning "Проблемы в max-messenger-host-secure.desktop"
    fi
fi

echo ""
log_success "Установка завершена!"
echo ""
echo "Ярлык установлен:"
echo "  🔒 MAX Messenger (Host Secure): $DESKTOP_DIR/max-messenger-host-secure.desktop"
echo ""
echo "Теперь вы можете:"
echo "  1. Найти приложение в меню 'MAX Messenger (Host Secure)'"
echo "  2. Закрепить на панели задач"
echo "  3. Запускать мессенджер одним кликом"
echo ""
echo "Для проверки запуска из терминала:"
echo "  gtk-launch max-messenger-host-secure"
echo "  или"
echo "  ${RUN_SCRIPT}"
