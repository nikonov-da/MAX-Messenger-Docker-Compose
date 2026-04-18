#!/usr/bin/env bash

CONTAINER_NAME="max_messenger"
NETWORK_NAME="max_isolated_network"

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            MAX Security Check - Проверка изоляции          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка сети
echo -e "${GREEN}=== 1. Изолированная сеть ===${NC}"
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    echo -e "${GREEN}✓ Сеть $NETWORK_NAME существует${NC}"
    ICC=$(docker network inspect "$NETWORK_NAME" | grep -o '"com.docker.network.bridge.enable_icc":"[^"]*"' | cut -d'"' -f4)
    if [ "$ICC" = "false" ]; then
        echo -e "  ${GREEN}✓ Межконтейнерное взаимодействие: ЗАПРЕЩЕНО${NC}"
    else
        echo -e "  ${RED}✗ Межконтейнерное взаимодействие: РАЗРЕШЕНО${NC}"
    fi
else
    echo -e "${RED}✗ Сеть $NETWORK_NAME не существует${NC}"
fi

# Проверка контейнера
echo ""
echo -e "${GREEN}=== 2. Запущенный контейнер ===${NC}"
if docker ps -q -f name=^/${CONTAINER_NAME}$ &> /dev/null; then
    echo -e "${GREEN}✓ Контейнер $CONTAINER_NAME запущен${NC}"

    # Капабилити
    CAPS=$(docker inspect "$CONTAINER_NAME" | grep -A20 "CapAdd" | grep -E '"[A-Z_]+"' | tr -d '",' | xargs)
    echo "  Капабилити: ${CAPS:-нет}"

    # Read-only root
    RO_READONLY=$(docker inspect "$CONTAINER_NAME" | grep -i "ReadonlyRootfs" | grep -o "true\|false")
    if [ "$RO_READONLY" = "true" ]; then
        echo -e "  ${GREEN}✓ Root ФС: Read-only${NC}"
    else
        echo -e "  ${RED}✗ Root ФС: Read-write${NC}"
    fi

    # Проверка доступа к /proc
    echo -n "  Доступ к /proc: "
    if docker exec "$CONTAINER_NAME" ls /proc >/dev/null 2>&1; then
        echo -e "${RED}ДОСТУП ЕСТЬ${NC}"
    else
        echo -e "${GREEN}ЗАПРЕЩЁН${NC}"
    fi

    # Проверка доступа к /sys
    echo -n "  Доступ к /sys: "
    if docker exec "$CONTAINER_NAME" ls /sys >/dev/null 2>&1; then
        echo -e "${RED}ДОСТУП ЕСТЬ${NC}"
    else
        echo -e "${GREEN}ЗАПРЕЩЁН${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Контейнер $CONTAINER_NAME не запущен${NC}"
fi

# Проверка GPU
echo ""
echo -e "${GREEN}=== 3. Аппаратное ускорение ===${NC}"
if command -v nvidia-smi &> /dev/null; then
    NVIDIA_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    echo -e "${GREEN}✓ NVIDIA GPU: $NVIDIA_GPU${NC}"

    if docker ps -q -f name=^/${CONTAINER_NAME}$ &> /dev/null; then
        echo -n "  GPU в контейнере: "
        if docker exec "$CONTAINER_NAME" nvidia-smi >/dev/null 2>&1; then
            echo -e "${GREEN}ДОСТУПЕН${NC}"
        else
            echo -e "${RED}НЕ ДОСТУПЕН${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ NVIDIA GPU не обнаружена${NC}"
fi

# Проверка профилей безопасности
echo ""
echo -e "${GREEN}=== 4. Профили безопасности ===${NC}"

# Seccomp
SECCOMP_PATH="$HOME/max-messenger/bin/seccomp-max.json"
if [ -f "$SECCOMP_PATH" ]; then
    echo -e "${GREEN}✓ Seccomp профиль: $SECCOMP_PATH${NC}"
else
    echo -e "${RED}✗ Seccomp профиль не найден${NC}"
fi

# AppArmor
if command -v apparmor_parser &> /dev/null; then
    if aa-status 2>/dev/null | grep -q "docker-max-messenger"; then
        echo -e "${GREEN}✓ AppArmor профиль: docker-max-messenger${NC}"
    else
        echo -e "${YELLOW}⚠ AppArmor профиль не загружен${NC}"
    fi
else
    echo -e "${YELLOW}⚠ AppArmor не установлен (только для Ubuntu/Debian)${NC}"
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Проверка завершена${NC}"
