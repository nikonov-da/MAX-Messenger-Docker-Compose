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
    prune)
        echo "🧹 Очистка..."
        docker compose down
        docker system prune -f
        ;;
    *)
        echo "Использование: $0 {up|up-d|down|restart|logs|build|status|exec|prune}"
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
        echo "  prune   - Очистка и остановка"
        exit 1
        ;;
esac
