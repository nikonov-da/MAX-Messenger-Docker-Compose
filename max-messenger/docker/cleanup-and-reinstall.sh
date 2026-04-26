#!/bin/bash
# cleanup-and-reinstall.sh - Безопасная очистка Docker

# Отключаем немедленный выход при ошибке
set +e

echo "=== Полная очистка и переустановка Docker ==="
echo ""

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

# Функция для безопасной проверки наличия процессов (исключая текущий скрипт)
check_processes() {
    # Ищем процессы, исключая текущий PID и grep
    ps aux | grep -E "$1" | grep -v grep | grep -v "$$" | grep -q .
    return $?
}

# Функция для безопасного убийства процессов (исключая текущий скрипт)
kill_processes_safe() {
    local pattern="$1"
    # Получаем PID процессов, исключая текущий
    local pids=$(ps aux | grep -E "$pattern" | grep -v grep | grep -v "$$" | awk '{print $2}')
    if [ -n "$pids" ]; then
        echo "$pids" | xargs sudo kill -9 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Функция для безопасной проверки наличия данных
has_data() {
    [ -n "$1" ]
    return $?
}

# 1. Остановка Docker
log_info "Остановка Docker..."
if systemctl is-active --quiet docker 2>/dev/null; then
    sudo systemctl stop docker 2>/dev/null
    sudo systemctl stop docker.socket 2>/dev/null
    log_success "Docker остановлен"
else
    log_warning "Docker уже остановлен"
fi

# 2. Проверка и убийство зависших процессов (безопасная версия)
log_info "Проверка зависших процессов..."
if check_processes "docker|containerd"; then
    log_info "Найдены процессы Docker, завершаем..."
    kill_processes_safe "docker"
    kill_processes_safe "containerd"
    sleep 2
    log_success "Процессы завершены"
else
    log_warning "Зависших процессов не найдено"
fi

# 3. Остановка и удаление контейнеров
log_info "Остановка и удаление контейнеров..."
CONTAINERS=$(docker ps -aq 2>/dev/null)
if has_data "$CONTAINERS"; then
    echo "$CONTAINERS" | while read container; do
        docker stop "$container" 2>/dev/null
        docker rm "$container" 2>/dev/null
    done
    log_success "Контейнеры удалены"
else
    log_warning "Контейнеров не найдено"
fi

# 4. Удаление образов
log_info "Удаление образов..."
IMAGES=$(docker images -q 2>/dev/null)
if has_data "$IMAGES"; then
    echo "$IMAGES" | while read image; do
        docker rmi -f "$image" 2>/dev/null
    done
    log_success "Образы удалены"
else
    log_warning "Образов не найдено"
fi

# 5. Удаление томов
log_info "Удаление томов..."
VOLUMES=$(docker volume ls -q 2>/dev/null)
if has_data "$VOLUMES"; then
    echo "$VOLUMES" | while read volume; do
        docker volume rm -f "$volume" 2>/dev/null
    done
    log_success "Тома удалены"
else
    log_warning "Томов не найдено"
fi

# 6. Удаление пользовательских сетей
log_info "Удаление пользовательских сетей..."
NETWORKS=$(docker network ls --filter "type=custom" -q 2>/dev/null)
if has_data "$NETWORKS"; then
    echo "$NETWORKS" | while read network; do
        docker network rm "$network" 2>/dev/null
    done
    log_success "Сети удалены"
else
    log_warning "Пользовательских сетей не найдено"
fi

# 7. Очистка системы
log_info "Очистка системы Docker..."
if docker system df -q 2>/dev/null | grep -q .; then
    docker system prune -f 2>/dev/null
    docker volume prune -f 2>/dev/null
    docker network prune -f 2>/dev/null
    log_success "Система очищена"
else
    log_warning "Нечего очищать"
fi

# 8. Проверка установки Docker перед удалением
log_info "Проверка установленных пакетов Docker..."
DOCKER_PACKAGES=$(rpm -qa 2>/dev/null | grep -E "docker-ce|containerd" | tr '\n' ' ')
if has_data "$DOCKER_PACKAGES"; then
    log_info "Найдены пакеты: $DOCKER_PACKAGES"
else
    log_warning "Пакеты Docker не найдены"
fi

# 9. Полное удаление Docker
log_info "Удаление пакетов Docker..."
if has_data "$DOCKER_PACKAGES"; then
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
    log_success "Пакеты Docker удалены"
else
    log_warning "Пакеты Docker уже удалены"
fi

# 10. Удаление всех данных Docker
log_info "Удаление конфигурационных файлов и данных..."
DATA_DIRS="/var/lib/docker /var/lib/containerd /etc/docker /run/docker /var/run/docker ~/.docker /var/run/docker/netns"
for dir in $DATA_DIRS; do
    if [ -e "$dir" ]; then
        sudo rm -rf "$dir" 2>/dev/null
        log_info "Удалено: $dir"
    fi
done
log_success "Данные Docker удалены"

# 11. Очистка кэша dnf
log_info "Очистка кэша DNF..."
sudo dnf clean all 2>/dev/null
log_success "Кэш очищен"

# 12. Переустановка Docker
log_info "Переустановка Docker..."

# Добавление репозитория
if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    sudo dnf install -y dnf-plugins-core 2>/dev/null
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null
    log_success "Репозиторий Docker добавлен"
else
    log_warning "Репозиторий Docker уже существует"
fi

# Установка Docker
log_info "Установка пакетов Docker..."
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if command -v docker &> /dev/null; then
    log_success "Docker установлен"
else
    log_error "Ошибка при установке Docker"
fi

# 13. Запуск Docker
log_info "Запуск Docker..."
sudo systemctl start docker 2>/dev/null
sudo systemctl enable docker 2>/dev/null
sudo usermod -aG docker $USER 2>/dev/null

if systemctl is-active --quiet docker 2>/dev/null; then
    log_success "Docker запущен"
else
    log_error "Docker не запустился"
fi

# 14. Проверка установки
log_info "Проверка Docker..."
docker version 2>/dev/null | head -5 || echo "Docker version: установлен"

echo ""
log_success "=== Очистка и переустановка завершены! ==="
echo ""
echo "РЕКОМЕНДАЦИИ:"
echo "1. Перезагрузите систему: sudo reboot"
echo "2. После перезагрузки пересоберите образ MAX Messenger:"
echo "   cd ~/max-messenger/docker"
echo "   docker build --no-cache -t max-messenger:latest ."
echo ""
read -p "Нажмите Enter для выхода..."
