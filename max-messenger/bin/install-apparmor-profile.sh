#!/bin/bash
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
