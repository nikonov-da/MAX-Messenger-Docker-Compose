#!/bin/bash

# Определение ОС
if [ -f /etc/fedora-release ]; then
    echo "Обнаружена Fedora. AppArmor не используется, используется SELinux."
    echo "Пропускаем установку AppArmor профиля."
    echo "Безопасность обеспечивается через Seccomp и капабилити."
    exit 0
fi

# Для Ubuntu/Debian
if command -v apt &> /dev/null; then
    # Установка AppArmor если не установлен
    if ! command -v apparmor_parser &> /dev/null; then
        echo "Установка AppArmor..."
        sudo apt install -y apparmor apparmor-utils
    fi

    # Создание директории если её нет
    sudo mkdir -p /etc/apparmor.d

    sudo tee /etc/apparmor.d/docker-max-messenger << 'EOF'
#include <tunables/global>

profile docker-max-messenger flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  deny /proc/** rw,
  deny /sys/** rw,
  deny /dev/** rw,
  deny /boot/** r,
  deny /etc/shadow rw,
  deny /etc/passwd rw,
  deny /root/** rw,
  deny /home/*/.ssh/** rw,

  /usr/bin/max rwix,
  /usr/share/max/** r,
  /home/*/.config/max/** rw,
  /tmp/** rw,
  /run/user/*/bus rw,
  /tmp/.X11-unix/X0 rw,

  capability setuid,
  capability setgid,
  capability net_raw,
  capability net_admin,

  network inet stream,
  network inet6 stream,
  network unix stream,

  deny network raw,
}
EOF

    sudo apparmor_parser -r /etc/apparmor.d/docker-max-messenger
    echo "AppArmor профиль установлен"
else
    echo "Неподдерживаемая ОС. Пропускаем установку AppArmor."
fi
