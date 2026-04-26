#!/usr/bin/env bash

NETWORK_NAME="max_isolated_network"
SUBNET="172.20.0.0/16"
GATEWAY="172.20.0.1"
BRIDGE_NAME="docker_max_br"

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
echo -e "${BLUE}║        Создание изолированной сети для MAX Messenger       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker не установлен"
    exit 1
fi

# Проверка существования сети
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    log_warning "Сеть $NETWORK_NAME уже существует"
    echo ""
    echo "Текущие параметры сети:"
    docker network inspect "$NETWORK_NAME" --format='  IPAM: {{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null
    echo "  Межконтейнерное взаимодействие: $(docker network inspect "$NETWORK_NAME" --format='{{index .Options "com.docker.network.bridge.enable_icc"}}' 2>/dev/null)"
    echo ""
    echo -n "Удалить и создать заново? (y/N): "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        # Останавливаем контейнеры, использующие сеть
        CONTAINERS=$(docker network inspect "$NETWORK_NAME" --format='{{range $k, $v := .Containers}}{{$k}} {{end}}' 2>/dev/null)
        if [ -n "$CONTAINERS" ]; then
            log_warning "Контейнеры, использующие сеть: $CONTAINERS"
            echo -n "Остановить их? (y/N): "
            read -r stop_answer
            if [[ "$stop_answer" =~ ^[Yy]$ ]]; then
                for c in $CONTAINERS; do
                    docker stop "$c" 2>/dev/null
                    docker rm "$c" 2>/dev/null
                done
                log_success "Контейнеры остановлены"
            fi
        fi
        docker network rm "$NETWORK_NAME"
        log_info "Сеть удалена"
    else
        log_info "Используем существующую сеть"
        echo ""
        echo "Информация о сети:"
        docker network inspect "$NETWORK_NAME" | grep -A10 "IPAM" | head -15
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
    --opt com.docker.network.bridge.name="$BRIDGE_NAME" \
    "$NETWORK_NAME"

if [ $? -eq 0 ]; then
    log_success "Сеть $NETWORK_NAME создана"
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    ПАРАМЕТРЫ СЕТИ                          ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  Имя сети:        $NETWORK_NAME                     ║"
    echo "║  Подсеть:         $SUBNET                            ║"
    echo "║  Шлюз:            $GATEWAY                               ║"
    echo "║  Мост:            $BRIDGE_NAME                            ║"
    echo "║  ICC (изоляция):  ЗАПРЕЩЕНО                                ║"
    echo "║  Masquerade:      ВКЛЮЧЕН (доступ в интернет)              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
else
    log_error "Не удалось создать сеть"
    exit 1
fi

# Настройка iptables (опционально)
if command -v sudo iptables &> /dev/null; then
    log_info "Настройка правил iptables для дополнительной изоляции..."

    # Проверяем, не добавлены ли уже правила
    if ! sudo iptables -C DOCKER-USER -i "$BRIDGE_NAME" -o lo -j DROP 2>/dev/null; then
        sudo iptables -I DOCKER-USER 1 -i "$BRIDGE_NAME" -o lo -j DROP 2>/dev/null
    fi
    if ! sudo iptables -C DOCKER-USER -i "$BRIDGE_NAME" -d 127.0.0.0/8 -j DROP 2>/dev/null; then
        sudo iptables -I DOCKER-USER 2 -i "$BRIDGE_NAME" -d 127.0.0.0/8 -j DROP 2>/dev/null
    fi
    log_success "Правила iptables добавлены"
fi

# Сохранение правил iptables (для сохранения после перезагрузки)
if command -v sudo iptables-save &> /dev/null; then
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null 2>&1 || true
    log_info "Правила iptables сохранены"
fi

echo ""
log_success "Готово!"
echo ""
echo "Полезные команды:"
echo "  docker network inspect $NETWORK_NAME          # Детальная информация о сети"
echo "  docker network ls                             # Список всех сетей"
echo "  sudo iptables -L DOCKER-USER -v               # Просмотр правил iptables"
echo "  docker run --rm --network $NETWORK_NAME alpine ping -c 2 8.8.8.8  # Тест доступа в интернет"
echo ""
