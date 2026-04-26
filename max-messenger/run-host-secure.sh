#!/usr/bin/env bash

# run-host-secure.sh - Запуск MAX Messenger в Host режиме с максимальной безопасностью

# Получение директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
cd "$PROJECT_DIR"

# Конфигурация
COMPOSE_FILE="docker-compose.host.secure.yml"
LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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

# Создание директории для логов с правильными правами
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
fi

# Проверка наличия compose файла
if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "Файл $COMPOSE_FILE не найден в $PROJECT_DIR"
    exit 1
fi

# Проверка Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker не установлен"
    exit 1
fi

# Проверка образа
if ! docker image inspect max-messenger:latest &> /dev/null; then
    log_error "Образ max-messenger:latest не найден"
    log_info "Выполните сборку: cd docker && docker build --no-cache -t max-messenger:latest ."
    exit 1
fi

# Функция для graceful shutdown
cleanup() {
    log_warning "Получен сигнал завершения, останавливаем контейнер..."
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null
    log_success "Очистка завершена"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Запуск
log_info "Запуск MAX Messenger в Host режиме с максимальной безопасностью..."
echo ""

# Логирование запуска (с проверкой прав)
LAUNCH_LOG="$LOG_DIR/launch_$TIMESTAMP.log"
{
    echo "=== MAX Messenger Host Secure Launch ==="
    echo "Timestamp: $(date)"
    echo "User: $(whoami)"
    echo "Project dir: $PROJECT_DIR"
    echo "Compose file: $COMPOSE_FILE"
    echo "Command: docker compose -f $COMPOSE_FILE up"
    echo "============================"
} | tee -a "$LAUNCH_LOG" 2>/dev/null || echo "⚠️ Не удалось записать лог"

# Запуск контейнера
docker compose -f "$COMPOSE_FILE" up

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    log_success "Сессия MAX Messenger завершена"
else
    log_error "Ошибка: код $EXIT_CODE"
fi

exit $EXIT_CODE
