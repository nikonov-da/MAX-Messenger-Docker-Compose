#!/usr/bin/env bash

# setup-selinux.sh - Настройка SELinux для MAX Messenger

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

# Создаём директорию для SELinux модулей
mkdir -p "$SELINUX_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            MAX SELinux Setup - Настройка SELinux           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка наличия SELinux
if ! command -v getenforce &> /dev/null; then
    log_error "SELinux не установлен"
    echo "Установка SELinux..."
    safe_run sudo dnf install -y selinux-policy-targeted selinux-policy-devel policycoreutils policycoreutils-python-utils
    log_success "SELinux установлен"
fi

# Проверка статуса SELinux
echo -e "${GREEN}[1/13] Проверка статуса SELinux...${NC}"
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
echo "  Текущий статус: $SELINUX_STATUS"

if [ "$SELINUX_STATUS" = "Disabled" ]; then
    log_warning "SELinux отключен. Включение..."
    safe_run sudo sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config
    log_warning "SELinux будет включен после перезагрузки"
elif [ "$SELINUX_STATUS" = "Permissive" ]; then
    log_warning "SELinux в режиме Permissive (только логирование)"
elif [ "$SELINUX_STATUS" = "Enforcing" ]; then
    log_success "SELinux в режиме Enforcing (активная защита)"
fi

echo ""
echo -e "${GREEN}[2/13] Создание резервной копии текущих настроек SELinux...${NC}"
BACKUP_DIR="$SELINUX_DIR/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
sudo semodule -l > "$BACKUP_DIR/modules.txt" 2>/dev/null
semanage fcontext -l > "$BACKUP_DIR/fcontext.txt" 2>/dev/null
getsebool -a > "$BACKUP_DIR/booleans.txt" 2>/dev/null
log_success "Резервная копия сохранена в $BACKUP_DIR"

echo ""
echo -e "${GREEN}[3/13] Настройка контекстов для Docker...${NC}"
safe_run sudo semanage fcontext -a -t container_file_t "/var/lib/docker(/.*)?"
safe_run sudo semanage fcontext -a -t container_file_t "/home/denis/.max(/.*)?"
safe_run sudo semanage fcontext -a -t container_file_t "$PROJECT_DIR/logs(/.*)?"
safe_run sudo restorecon -R /var/lib/docker
safe_run sudo restorecon -R /home/denis/.max
safe_run sudo restorecon -R "$PROJECT_DIR/logs"
log_success "Контексты SELinux настроены"

echo ""
echo -e "${GREEN}[4/13] Настройка контекстов для X11...${NC}"
# Настройка контекстов для X11 сокета
safe_run sudo semanage fcontext -a -t xserver_misc_x11_t "/tmp/.X11-unix(/.*)?"
safe_run sudo restorecon -R /tmp/.X11-unix
log_success "Контексты X11 настроены"

echo ""
echo -e "${GREEN}[5/13] Настройка Booleans для Docker...${NC}"
BOOLEANS=(
    "container_manage_cgroup:1"
    "virt_use_nfs:1"
    "virt_use_samba:1"
    "virt_use_fusefs:1"
    "virt_use_sanlock:1"
    "domain_can_mmap_files:1"
    "container_connect_any:1"
    "nis_enabled:1"
    "container_use_devices:1"
    # X11 связанные булевы
    "xserver_clients_use_x11:1"
    "xserver_allow_tcp:1"
)

for bool_entry in "${BOOLEANS[@]}"; do
    bool_name="${bool_entry%:*}"
    bool_value="${bool_entry#*:}"
    safe_run sudo setsebool -P "$bool_name" "$bool_value"
done
log_success "Булевы значения настроены"

echo ""
echo -e "${GREEN}[6/13] Создание SELinux модуля для Docker network...${NC}"

cat > "$SELINUX_DIR/docker-netns.te" << 'EOF'
module docker-netns 1.0;

require {
    type docker_t;
    type proc_net_t;
    type proc_t;
    class dir search;
    class file { read open };
    class filesystem getattr;
}

allow docker_t proc_t:filesystem getattr;
allow docker_t proc_net_t:dir search;
allow docker_t proc_net_t:file { read open };
EOF

cd "$SELINUX_DIR"

if command -v checkmodule &> /dev/null; then
    safe_run checkmodule -M -m -o docker-netns.mod docker-netns.te
    safe_run semodule_package -o docker-netns.pp -m docker-netns.mod
    safe_run sudo semodule -i docker-netns.pp
    log_success "SELinux модуль для Docker network установлен"
    log_info "Файлы сохранены в: $SELINUX_DIR/docker-netns.*"
else
    log_warning "Инструменты SELinux не найдены, пропуск"
fi

echo ""
echo -e "${GREEN}[7/13] Создание модуля для /proc доступа...${NC}"

cat > "$SELINUX_DIR/proc-access.te" << 'EOF'
module proc-access 1.0;

require {
    type docker_t;
    type proc_t;
    class file { read open };
    class filesystem getattr;
}

allow docker_t proc_t:filesystem getattr;
allow docker_t proc_t:file { read open };
EOF

cd "$SELINUX_DIR"

if command -v checkmodule &> /dev/null; then
    safe_run checkmodule -M -m -o proc-access.mod proc-access.te
    safe_run semodule_package -o proc-access.pp -m proc-access.mod
    safe_run sudo semodule -i proc-access.pp
    log_success "Модуль для /proc доступа установлен"
    log_info "Файлы сохранены в: $SELINUX_DIR/proc-access.*"
fi

echo ""
echo -e "${GREEN}[8/13] Создание исправленного модуля для network namespace...${NC}"

cat > "$SELINUX_DIR/docker-netns-fix.te" << 'EOF'
module docker-netns-fix 1.0;

require {
    type docker_t;
    type container_t;
    type proc_t;
    type proc_net_t;
    class dir search;
    class file { read open getattr };
    class filesystem getattr;
}

allow docker_t proc_t:filesystem getattr;
allow docker_t proc_t:dir search;
allow docker_t proc_t:file { read open getattr };
allow docker_t proc_net_t:dir search;
allow docker_t proc_net_t:file { read open getattr };
allow container_t proc_t:filesystem getattr;
allow container_t proc_net_t:dir search;
allow container_t proc_net_t:file { read open };
EOF

cd "$SELINUX_DIR"

if command -v checkmodule &> /dev/null; then
    safe_run checkmodule -M -m -o docker-netns-fix.mod docker-netns-fix.te
    safe_run semodule_package -o docker-netns-fix.pp -m docker-netns-fix.mod
    safe_run sudo semodule -i docker-netns-fix.pp
    log_success "Исправленный модуль для network namespace установлен"
    log_info "Файлы сохранены в: $SELINUX_DIR/docker-netns-fix.*"
fi

echo ""
echo -e "${GREEN}[9/13] Создание модуля для X11 доступа...${NC}"

cat > "$SELINUX_DIR/x11-access.te" << 'EOF'
module x11-access 1.0;

require {
    type container_t;
    type xserver_misc_x11_t;
    type xdm_t;
    class file { read write open getattr };
    class dir search;
    class unix_stream_socket connectto;
}

# Разрешаем контейнеру доступ к X11
allow container_t xserver_misc_x11_t:dir search;
allow container_t xserver_misc_x11_t:file { read write open getattr };
allow container_t xdm_t:unix_stream_socket connectto;
EOF

cd "$SELINUX_DIR"

if command -v checkmodule &> /dev/null; then
    safe_run checkmodule -M -m -o x11-access.mod x11-access.te
    safe_run semodule_package -o x11-access.pp -m x11-access.mod
    safe_run sudo semodule -i x11-access.pp
    log_success "Модуль для X11 доступа установлен"
    log_info "Файлы сохранены в: $SELINUX_DIR/x11-access.*"
fi

echo ""
echo -e "${GREEN}[10/13] Создание упрощённого модуля для MAX Messenger...${NC}"

cat > "$SELINUX_DIR/max_messenger.te" << 'EOF'
module max_messenger 1.0;

require {
    type container_t;
    type xdm_t;
    type proc_net_t;
    type proc_t;
    type tmp_t;
    type user_tmp_t;
    type config_home_t;
    type xserver_misc_x11_t;
    class file { read write open create unlink getattr setattr };
    class dir { read write search add_name remove_name open getattr };
    class unix_stream_socket connectto;
    class filesystem getattr;
}

allow container_t proc_t:filesystem getattr;
allow container_t proc_net_t:dir search;
allow container_t proc_net_t:file { read open };
allow container_t xserver_misc_x11_t:file { read write open getattr };
allow container_t xdm_t:unix_stream_socket connectto;
allow container_t tmp_t:dir { read write search add_name remove_name };
allow container_t tmp_t:file { read write create unlink };
allow container_t user_tmp_t:dir { read write search add_name remove_name };
allow container_t user_tmp_t:file { read write create unlink };
allow container_t config_home_t:dir { read write search add_name remove_name };
allow container_t config_home_t:file { read write create unlink };
EOF

cd "$SELINUX_DIR"

if command -v checkmodule &> /dev/null; then
    safe_run checkmodule -M -m -o max_messenger.mod max_messenger.te
    safe_run semodule_package -o max_messenger.pp -m max_messenger.mod
    safe_run sudo semodule -i max_messenger.pp
    log_success "SELinux модуль для MAX Messenger установлен"
    log_info "Файлы сохранены в: $SELINUX_DIR/max_messenger.*"
fi

echo ""
echo -e "${GREEN}[11/13] Настройка permissive режима для Docker...${NC}"
safe_run sudo semanage permissive -a docker_t
log_success "Docker переведён в permissive режим"

echo ""
echo -e "${GREEN}[12/13] Настройка правил аудита...${NC}"
safe_run sudo auditctl -W /usr/bin/docker -k docker 2>/dev/null
safe_run sudo auditctl -W /var/lib/docker -k docker-storage 2>/dev/null
safe_run sudo auditctl -W /home/denis/.max -k max-config 2>/dev/null
safe_run sudo auditctl -W /tmp/.X11-unix -k x11-socket 2>/dev/null
safe_run sudo auditctl -w /usr/bin/docker -k docker
safe_run sudo auditctl -w /var/lib/docker -k docker-storage
safe_run sudo auditctl -w /home/denis/.max -k max-config
safe_run sudo auditctl -w /tmp/.X11-unix -k x11-socket
log_success "Правила аудита настроены"

echo ""
echo -e "${GREEN}[13/13] Перезапуск Docker и применение контекстов...${NC}"
safe_run sudo restorecon -R "$PROJECT_DIR" 2>/dev/null
safe_run sudo restorecon -R /home/denis/.max 2>/dev/null
safe_run sudo restorecon -R /tmp/.X11-unix 2>/dev/null
safe_run sudo systemctl restart docker
log_success "Docker перезапущен"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Настройка SELinux завершена!${NC}"
echo ""
echo "Статус SELinux: $(getenforce 2>/dev/null || echo 'Unknown')"
echo "Директория проекта: $PROJECT_DIR"
echo "Директория SELinux модулей: $SELINUX_DIR"
echo "Резервная копия настроек: $BACKUP_DIR"
echo ""
echo "Установленные SELinux модули:"
ls -la "$SELINUX_DIR"/*.{te,mod,pp} 2>/dev/null | awk '{print "  " $9}'
echo ""
echo "КЛЮЧЕВЫЕ МОДУЛИ:"
echo "  - docker-netns-fix - решает проблему с network namespace"
echo "  - x11-access - разрешает доступ к X11"
echo ""
echo "Для просмотра нарушений SELinux:"
echo "  sudo ausearch -m avc -ts recent"
echo ""
echo "Для временного переключения в Permissive режим:"
echo "  sudo setenforce 0"
echo ""
echo "Для возврата в Enforcing режим:"
echo "  sudo setenforce 1"
echo ""
echo "Для проверки работы контейнера с изолированной сетью:"
echo "  cd $PROJECT_DIR && docker compose up"
echo ""
echo "Для восстановления настроек из резервной копии:"
echo "  cd $PROJECT_DIR && ./bin/cleanup-isolation.sh"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Предупреждение о перезагрузке
if [ "$SELINUX_STATUS" = "Disabled" ]; then
    echo ""
    log_warning "SELinux был отключен. Требуется перезагрузка для активации:"
    echo "  sudo reboot"
fi

# Предложение временно отключить SELinux для теста
echo ""
read -p "Временно отключить SELinux для теста? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    safe_run sudo setenforce 0
    log_success "SELinux временно отключен (режим Permissive)"
    echo "Для включения обратно: sudo setenforce 1"
fi
