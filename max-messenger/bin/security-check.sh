#!/bin/bash

CONTAINER_NAME="max_messenger"

echo "=== Проверка изоляции контейнера ==="
echo ""

echo "1. Капабилити контейнера:"
docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -A 10 "CapAdd\|CapDrop" || echo "Контейнер не запущен"

echo ""
echo "2. Проверка доступа к /proc:"
docker exec "$CONTAINER_NAME" ls /proc 2>&1 | head -3 || echo "Доступ запрещён"

echo ""
echo "3. Проверка доступа к /sys:"
docker exec "$CONTAINER_NAME" ls /sys 2>&1 | head -3 || echo "Доступ запрещён"

echo ""
echo "4. Проверка сетевой изоляции:"
docker exec "$CONTAINER_NAME" ip addr show 2>/dev/null | grep -E "inet|eth" || echo "Сеть изолирована"

echo ""
echo "5. Проверка GPU:"
docker exec "$CONTAINER_NAME" nvidia-smi 2>/dev/null | grep -E "GeForce|Tesla" || echo "GPU не доступен"

echo "=== Проверка завершена ==="
