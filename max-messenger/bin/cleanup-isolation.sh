#!/usr/bin/env bash

# cleanup-isolation.sh - Удаление изолированной сети и сброс настроек SELinux

# Отключаем выход при ошибках
set +e

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

# Определение путей
PROJECT_DIR="$HOME/max-messenger"
SELINUX_DIR="$PROJECT_DIR/selinux"

# Функция для безопасного выполнения команд
safe_run() {
    "$@" 2>/dev/null || true
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      MAX Cleanup - Удаление изоляции и сброс SELinux       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Подтверждение действия
echo -e "${YELLOW}ВНИМАНИЕ! Этот скрипт удалит:${NC}"
echo "  - Изолированную сеть max_isolated_network"
echo "  - SELinux модули для MAX Messenger и Docker"
echo "  - Контексты SELinux для Docker и X11"
echo "  - Правила аудита"
echo "  - Файлы SELinux модулей из $SELINUX_DIR"
echo ""
read -p "Продолжить? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "Операция отменена"
    exit 0
fi

echo ""
echo -e "${GREEN}[1/10] Остановка контейнера MAX Messenger...${NC}"
safe_run docker stop max_messenger
safe_run docker rm max_messenger
log_success "Контейнер остановлен и удалён"

echo ""
echo -e "${GREEN}[2/10] Удаление изолированной сети...${NC}"
if docker network inspect max_isolated_network &>/dev/null; then
    safe_run docker network rm max_isolated_network
    log_success "Сеть max_isolated_network удалена"
else
    log_warning "Сеть max_isolated_network не найдена"
fi

echo ""
echo -e "${GREEN}[3/10] Удаление SELinux модулей...${NC}"

# Список модулей для удаления (все модули из setup-selinux.sh)
MODULES_TO_REMOVE=(
    "docker-netns"
    "proc-access"
    "docker-netns-fix"
    "x11-access"
    "max_messenger"
)

# Получаем список всех установленных модулей
INSTALLED_MODULES=$(sudo semodule -l 2>/dev/null | awk '{print $1}')

for module in "${MODULES_TO_REMOVE[@]}"; do
    if echo "$INSTALLED_MODULES" | grep -q "^$module$"; then
        safe_run sudo semodule -r "$module"
        log_success "Модуль $module удалён"
    else
        log_warning "Модуль $module не найден"
    fi
done

echo ""
echo -e "${GREEN}[4/10] Удаление permissive режима для Docker...${NC}"
if sudo semanage permissive -l 2>/dev/null | grep -q "docker_t"; then
    safe_run sudo semanage permissive -d docker_t
    log_success "Permissive режим для docker_t отключён"
else
    log_warning "Permissive режим для docker_t не найден"
fi

echo ""
echo -e "${GREEN}[5/10] Удаление контекстов SELinux...${NC}"
# Удаление добавленных контекстов (из setup-selinux.sh)
CONTEXTS_TO_REMOVE=(
    "/var/lib/docker(/.*)?"
    "/home/denis/.max(/.*)?"
    "$PROJECT_DIR/logs(/.*)?"
    "/tmp/.X11-unix(/.*)?"
)

for context in "${CONTEXTS_TO_REMOVE[@]}"; do
    if sudo semanage fcontext -l 2>/dev/null | grep -q "$context"; then
        safe_run sudo semanage fcontext -d "$context" 2>/dev/null
        log_success "Контекст $context удалён"
    else
        log_warning "Контекст $context не найден"
    fi
done
log_success "Контексты SELinux удалены"

echo ""
echo -e "${GREEN}[6/10] Удаление правил аудита...${NC}"
safe_run sudo auditctl -W /usr/bin/docker -k docker 2>/dev/null
safe_run sudo auditctl -W /var/lib/docker -k docker-storage 2>/dev/null
safe_run sudo auditctl -W /home/denis/.max -k max-config 2>/dev/null
safe_run sudo auditctl -W /tmp/.X11-unix -k x11-socket 2>/dev/null
log_success "Правила аудита удалены"

echo ""
echo -e "${GREEN}[7/10] Сброс булевых значений...${NC}"
# Сброс булевых значений (из setup-selinux.sh)
BOOLEANS_TO_RESET=(
    "container_manage_cgroup"
    "virt_use_nfs"
    "virt_use_samba"
    "virt_use_fusefs"
    "virt_use_sanlock"
    "domain_can_mmap_files"
    "container_connect_any"
    "nis_enabled"
    "container_use_devices"
    "xserver_clients_use_x11"
    "xserver_allow_tcp"
)

for bool in "${BOOLEANS_TO_RESET[@]}"; do
    safe_run sudo setsebool -P "$bool" 0 2>/dev/null
done
log_success "Булевы значения сброшены"

echo ""
echo -e "${GREEN}[8/10] Удаление файлов SELinux модулей из проекта...${NC}"
if [ -d "$SELINUX_DIR" ]; then
    # Удаляем скомпилированные файлы, но оставляем исходники .te
    safe_run rm -f "$SELINUX_DIR"/*.mod "$SELINUX_DIR"/*.pp 2>/dev/null
    log_success "Скомпилированные файлы модулей удалены из $SELINUX_DIR"
    log_info "Исходные файлы .te сохранены в $SELINUX_DIR"

    # Опционально: удаление всей директории
    read -p "Удалить всю директорию $SELINUX_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        safe_run rm -rf "$SELINUX_DIR"
        log_success "Директория $SELINUX_DIR удалена"
    fi
else
    log_warning "Директория $SELINUX_DIR не найдена"
fi

echo ""
echo -e "${GREEN}[9/10] Очистка правил iptables...${NC}"
BRIDGE_NAME="docker_max_br"
if command -v sudo iptables &> /dev/null; then
    # Удаляем правила, если они существуют
    if sudo iptables -C DOCKER-USER -i "$BRIDGE_NAME" -o lo -j DROP 2>/dev/null; then
        sudo iptables -D DOCKER-USER -i "$BRIDGE_NAME" -o lo -j DROP 2>/dev/null
        log_success "Правило iptables для lo удалено"
    fi
    if sudo iptables -C DOCKER-USER -i "$BRIDGE_NAME" -d 127.0.0.0/8 -j DROP 2>/dev/null; then
        sudo iptables -D DOCKER-USER -i "$BRIDGE_NAME" -d 127.0.0.0/8 -j DROP 2>/dev/null
        log_success "Правило iptables для 127.0.0.0/8 удалено"
    fi
fi

echo ""
echo -e "${GREEN}[10/10] Перезапуск Docker и восстановление контекстов...${NC}"
safe_run sudo restorecon -R /var/lib/docker 2>/dev/null
safe_run sudo restorecon -R /home/denis/.max 2>/dev/null
safe_run sudo restorecon -R "$PROJECT_DIR" 2>/dev/null
safe_run sudo restorecon -R /tmp/.X11-unix 2>/dev/null
safe_run sudo systemctl restart docker
log_success "Docker перезапущен"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Очистка изоляции завершена!${NC}"
echo ""
echo "Статус SELinux: $(getenforce 2>/dev/null || echo 'Unknown')"
echo ""
echo "Что было сделано:"
echo "  ✅ Контейнер остановлен и удалён"
echo "  ✅ Сеть max_isolated_network удалена"
echo "  ✅ SELinux модули удалены (docker-netns, proc-access, docker-netns-fix, x11-access, max_messenger)"
echo "  ✅ Permissive режим отключён"
echo "  ✅ Контексты SELinux удалены (включая X11)"
echo "  ✅ Правила аудита удалены"
echo "  ✅ Булевы значения сброшены (включая X11)"
echo "  ✅ Файлы модулей очищены"
echo "  ✅ Правила iptables удалены"
echo "  ✅ Docker перезапущен"
echo ""
echo "Остаточные файлы:"
echo "  - Исходные политики: $SELINUX_DIR/*.te (если не удалены)"
echo "  - Резервные копии: $SELINUX_DIR/backup-*"
echo ""
echo "Для полного сброса SELinux к настройкам по умолчанию:"
echo "  sudo restorecon -Rv /"
echo ""
echo "Для удаления директории проекта полностью:"
echo "  rm -rf $PROJECT_DIR"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
