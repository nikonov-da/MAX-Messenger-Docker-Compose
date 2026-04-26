#!/usr/bin/env bash
# list-selinux-modules.sh - Просмотр установленных SELinux модулей

echo "=== Установленные SELinux модули ==="
sudo semodule -l | sort

echo ""
echo "=== Permissive режимы ==="
sudo semanage permissive -l

echo ""
echo "=== Контексты SELinux для MAX ==="
sudo semanage fcontext -l | grep -E "max|docker" || echo "Не найдены"
