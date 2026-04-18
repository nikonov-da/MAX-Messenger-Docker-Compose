#!/usr/bin/env bash

# setup-selinux.sh - Настройка SELinux для MAX Messenger

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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            MAX SELinux Setup - Настройка SELinux           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка наличия SELinux
if ! command -v getenforce &> /dev/null; then
    log_error "SELinux не установлен"
    echo "Установка SELinux..."
    sudo dnf install -y selinux-policy-targeted selinux-policy-devel policycoreutils policycoreutils-python-utils
    log_success "SELinux установлен"
fi

# Проверка статуса SELinux
echo -e "${GREEN}[1/6] Проверка статуса SELinux...${NC}"
SELINUX_STATUS=$(getenforce)
echo "  Текущий статус: $SELINUX_STATUS"

if [ "$SELINUX_STATUS" = "Disabled" ]; then
    log_warning "SELinux отключен. Включение..."
    sudo sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config
    log_warning "SELinux будет включен после перезагрузки"
elif [ "$SELINUX_STATUS" = "Permissive" ]; then
    log_warning "SELinux в режиме Permissive (только логирование)"
elif [ "$SELINUX_STATUS" = "Enforcing" ]; then
    log_success "SELinux в режиме Enforcing (активная защита)"
fi

echo ""
echo -e "${GREEN}[2/6] Настройка контекстов для Docker...${NC}"
# Установка правильных контекстов для Docker
sudo semanage fcontext -a -t container_file_t "/var/lib/docker(/.*)?" 2>/dev/null
sudo semanage fcontext -a -t container_file_t "/home/denis/.max(/.*)?" 2>/dev/null
sudo semanage fcontext -a -t container_file_t "/home/denis/max-messenger/logs(/.*)?" 2>/dev/null
sudo restorecon -R /var/lib/docker 2>/dev/null
sudo restorecon -R /home/denis/.max 2>/dev/null
sudo restorecon -R /home/denis/max-messenger/logs 2>/dev/null
log_success "Контексты SELinux настроены"

echo ""
echo -e "${GREEN}[3/6] Настройка Booleans для Docker...${NC}"
# Настройка SELinux булевых значений для Docker
sudo setsebool -P container_manage_cgroup 1
sudo setsebool -P virt_use_nfs 1
sudo setsebool -P virt_use_samba 1
sudo setsebool -P virt_use_fusefs 1
sudo setsebool -P virt_use_sanlock 1
log_success "Булевы значения настроены"

echo ""
echo -e "${GREEN}[4/6] Создание пользовательского SELinux модуля для MAX Messenger...${NC}"

# Создание директории для модуля
mkdir -p ~/max-messenger/selinux
cd ~/max-messenger/selinux

# Создание политики SELinux для MAX Messenger
cat > max_messenger.te << 'EOF'
module max_messenger 1.0;

require {
    type container_t;
    type xdm_t;
    type xdm_home_t;
    type tmp_t;
    type user_tmp_t;
    type user_home_t;
    type user_home_dir_t;
    type config_home_t;
    type cache_home_t;
    type xserver_misc_x11_t;
    type xdm_x11_tmp_t;
    class file { read write execute open create unlink getattr setattr };
    class dir { read write search add_name remove_name open getattr };
    class sock_file { read write unlink };
    class unix_stream_socket connectto;
    class process transition;
}

# Разрешение доступа к X11
allow container_t xserver_misc_x11_t:file { read write open getattr };
allow container_t xdm_x11_tmp_t:file { read write open getattr };
allow container_t xdm_t:unix_stream_socket connectto;

# Разрешение доступа к домашней директории
allow container_t user_home_dir_t:dir { read search open getattr };
allow container_t user_home_t:dir { read search open getattr };
allow container_t config_home_t:dir { read write search add_name remove_name };
allow container_t config_home_t:file { read write create unlink };
allow container_t cache_home_t:dir { read write search add_name remove_name };
allow container_t cache_home_t:file { read write create unlink };
allow container_t user_tmp_t:dir { read write search add_name remove_name };
allow container_t user_tmp_t:file { read write create unlink };

# Разрешение доступа к временным файлам
allow container_t tmp_t:dir { read write search add_name remove_name };
allow container_t tmp_t:file { read write create unlink };

# Разрешение доступа к сокетам
allow container_t xdm_t:unix_stream_socket connectto;

# Переход процесса
allow container_t xdm_t:process transition;
EOF

# Компиляция и установка модуля
if command -v checkmodule &> /dev/null; then
    checkmodule -M -m -o max_messenger.mod max_messenger.te
    semodule_package -o max_messenger.pp -m max_messenger.mod
    sudo semodule -i max_messenger.pp
    log_success "SELinux модуль для MAX Messenger установлен"
else
    log_warning "Инструменты SELinux не найдены, модуль не создан"
fi

echo ""
echo -e "${GREEN}[5/6] Настройка правил аудита...${NC}"
# Настройка аудита для отслеживания нарушений SELinux
sudo auditctl -w /usr/bin/docker -k docker
sudo auditctl -w /var/lib/docker -k docker-storage
sudo auditctl -w /home/denis/.max -k max-config
log_success "Правила аудита настроены"

echo ""
echo -e "${GREEN}[6/6] Проверка и применение контекстов...${NC}"
# Применение контекстов к файлам MAX Messenger
sudo restorecon -R /home/denis/max-messenger 2>/dev/null
sudo restorecon -R /home/denis/.max 2>/dev/null
sudo restorecon -R /tmp/.X11-unix 2>/dev/null

log_success "Контексты применены"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Настройка SELinux завершена!${NC}"
echo ""
echo "Статус SELinux: $(getenforce)"
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
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Предупреждение о перезагрузке
if [ "$SELINUX_STATUS" = "Disabled" ]; then
    echo ""
    log_warning "SELinux был отключен. Требуется перезагрузка для активации:"
    echo "  sudo reboot"
fi
