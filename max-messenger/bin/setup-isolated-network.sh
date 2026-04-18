#!/usr/bin/env bash

NETWORK_NAME="max_isolated_network"
SUBNET="172.20.0.0/16"
GATEWAY="172.20.0.1"

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

echo -e "${BLUE}=== Создание изолированной сети для MAX Messenger ===${NC}"
echo ""

# Проверка существования сети
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    log_warning "Сеть $NETWORK_NAME уже существует"
    echo -n "Удалить и создать заново? (y/N): "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        docker network rm "$NETWORK_NAME"
        log_info "Сеть удалена"
    else
        log_info "Используем существующую сеть"
        docker network inspect "$NETWORK_NAME" | grep -A5 "IPAM"
        exit 0
    fi
fi

# Создание сети
log_info "Создание изолированной сети $NETWORK_NAME..."
docker network create \
    --driver bridge \
    --subnet="$SUBNET" \
    --gateway="$GATEWAY" \
    --opt com.docker.network.bridge.enable_icc=false \
    --opt com.docker.network.bridge.enable_ip_masquerade=true \
    --opt com.docker.network.bridge.name=docker_max_br \
    "$NETWORK_NAME"

if [ $? -eq 0 ]; then
    log_success "Сеть $NETWORK_NAME создана"
    echo ""
    echo "Параметры сети:"
    echo "  Имя: $NETWORK_NAME"
    echo "  Подсеть: $SUBNET"
    echo "  Шлюз: $GATEWAY"
    echo "  Межконтейнерное взаимодействие: ЗАПРЕЩЕНО"
else
    log_error "Не удалось создать сеть"
    exit 1
fi

# Настройка iptables (опционально)
if command -v sudo iptables &> /dev/null; then
    log_info "Настройка правил iptables..."
    sudo iptables -I DOCKER-USER 1 -i docker_max_br -o lo -j DROP 2>/dev/null
    sudo iptables -I DOCKER-USER 2 -i docker_max_br -d 127.0.0.0/8 -j DROP 2>/dev/null
    log_success "Правила iptables добавлены"
fi

echo ""
log_success "Готово!"
echo "Для просмотра информации о сети: docker network inspect $NETWORK_NAME"
