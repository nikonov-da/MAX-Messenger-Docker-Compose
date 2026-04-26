#!/bin/bash
# test-security-levels.sh

set -e

PROJECT_DIR="$HOME/max-messenger"
cd "$PROJECT_DIR"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Результаты тестов
declare -a RESULTS
TIMEOUT=60

# Функция тестирования уровня
test_level() {
    local level=$1
    local compose_file="docker-compose.host.${level}.yml"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "🔒 Тестирование уровня безопасности: ${level}"
    echo "📄 Файл: ${compose_file}"
    echo "════════════════════════════════════════════════════════════"

    # Проверка существования файла
    if [ ! -f "$compose_file" ]; then
        log_error "Файл $compose_file не найден"
        RESULTS+=("${level}: ❌ ФАЙЛ НЕ НАЙДЕН")
        return 1
    fi

    # Очистка перед тестом
    log_info "Очистка..."
    docker compose -f "$compose_file" down 2>/dev/null || true

    # Запуск с таймаутом
    log_info "Запуск контейнера (таймаут ${TIMEOUT} сек)..."

    # Запускаем в фоне и ждём
    docker compose -f "$compose_file" up -d 2>&1

    if [ $? -ne 0 ]; then
        log_error "Контейнер не запустился (ошибка Docker)"
        RESULTS+=("${level}: ❌ НЕ ЗАПУСТИЛСЯ")
        docker compose -f "$compose_file" down 2>/dev/null || true
        return 1
    fi

    # Ждём запуска приложения
    log_info "Ожидание запуска приложения (5 сек)..."
    sleep 5

    # Проверка, жив ли контейнер
    if docker ps | grep -q "max_messenger"; then
        # Проверяем, не упало ли приложение внутри контейнера
        local status=$(docker inspect -f '{{.State.Status}}' max_messenger 2>/dev/null)
        local health=$(docker inspect -f '{{.State.Health.Status}}' max_messenger 2>/dev/null)

        if [ "$status" = "running" ]; then
            log_success "Контейнер работает (статус: $status, health: $health)"
            RESULTS+=("${level}: ✅ РАБОТАЕТ")

            # Останавливаем контейнер
            docker compose -f "$compose_file" down
            return 0
        else
            log_error "Контейнер упал (статус: $status)"
            RESULTS+=("${level}: ❌ УПАЛ")

            # Логи для диагностики
            log_warning "Последние логи:"
            docker compose -f "$compose_file" logs --tail=10 2>/dev/null || true

            docker compose -f "$compose_file" down 2>/dev/null || true
            return 1
        fi
    else
        log_error "Контейнер не запустился или моментально упал"
        RESULTS+=("${level}: ❌ МГНОВЕННО УПАЛ")
        docker compose -f "$compose_file" down 2>/dev/null || true
        return 1
    fi
}

# Создание всех файлов уровней
create_level_files() {
    log_info "Создание файлов уровней безопасности..."

    # Уровень 1
    cat > docker-compose.host.level1.yml << 'EOF'
[вставить содержимое level1]
EOF

    # Уровень 2
    cat > docker-compose.host.level2.yml << 'EOF'
[вставить содержимое level2]
EOF

    # Уровень 3
    cat > docker-compose.host.level3.yml << 'EOF'
[вставить содержимое level3]
EOF

    # Уровень 4
    cat > docker-compose.host.level4.yml << 'EOF'
[вставить содержимое level4]
EOF

    # Уровень 5
    cat > docker-compose.host.level5.yml << 'EOF'
[вставить содержимое level5]
EOF

    log_success "Файлы уровней созданы"
}

# Главная функция
main() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║            Тестирование уровней безопасности               ║"
    echo "║                     MAX Messenger                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"

    # Создание файлов (опционально)
    read -p "Создать файлы уровней? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_level_files
    fi

    # Тестирование каждого уровня
    for level in level1 level2 level3 level4 level5; do
        test_level "$level"
    done

    # Вывод результатов
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "📊 РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ"
    echo "════════════════════════════════════════════════════════════"

    local working_level=""
    for result in "${RESULTS[@]}"; do
        echo "  $result"
        if [[ "$result" == *"✅ РАБОТАЕТ"* ]]; then
            working_level=$(echo "$result" | cut -d: -f1)
        fi
    done

    echo ""
    if [ -n "$working_level" ]; then
        log_success "Последний рабочий уровень: $working_level"
        echo ""
        echo "Для запуска используйте:"
        echo "  docker compose -f docker-compose.host.${working_level}.yml up"
    else
        log_error "Ни один уровень не работает!"
        echo "Проверьте базовую конфигурацию docker-compose.host.working.yml"
    fi

    # Предложение сохранить последний рабочий уровень
    if [ -n "$working_level" ]; then
        echo ""
        read -p "Сохранить ${working_level} как рабочий? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "docker-compose.host.${working_level}.yml" "docker-compose.host.secure.yml"
            log_success "Сохранён как docker-compose.host.secure.yml"
        fi
    fi
}

# Запуск
main
