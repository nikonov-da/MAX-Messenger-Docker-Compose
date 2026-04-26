#!/bin/bash
# force-cleanup.sh - Принудительная очистка без docker команд

echo "=== Принудительная очистка Docker (без использования docker команд) ==="

# 1. Остановка всех процессов Docker
echo "Остановка процессов Docker..."
sudo systemctl stop docker
sudo systemctl stop docker.socket
sudo pkill -9 docker
sudo pkill -9 containerd
sudo pkill -9 dockerd
sleep 3

# 2. Удаление всех файлов Docker
echo "Удаление файлов Docker..."
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/docker
sudo rm -rf /run/docker
sudo rm -rf /var/run/docker
sudo rm -rf /var/run/docker.sock
sudo rm -rf /var/run/docker/netns/*
sudo rm -rf ~/.docker

# 3. Удаление конфигурации
echo "Удаление конфигурации..."
sudo rm -f /etc/systemd/system/docker.service
sudo rm -f /etc/systemd/system/docker.socket
sudo systemctl daemon-reload

# 4. Удаление пакетов
echo "Удаление пакетов Docker..."
sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Очистка кэша
echo "Очистка кэша..."
sudo dnf clean all

echo "Готово! Теперь можно переустановить Docker."
echo "Запустите: sudo dnf install -y docker-ce docker-ce-cli containerd.io"
