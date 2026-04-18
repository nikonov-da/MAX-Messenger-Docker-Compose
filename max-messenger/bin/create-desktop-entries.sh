#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$DESKTOP_DIR"

ICON_MAIN="$SCRIPT_DIR/MAX-1024x1024.png"
ICON_DEBUG="$SCRIPT_DIR/MAX-DEBUG-TOOL.png"
ICON_FIX="$SCRIPT_DIR/MAX-FIX-TOOL.png"

[ ! -f "$ICON_MAIN" ] && ICON_MAIN=""
[ ! -f "$ICON_DEBUG" ] && ICON_DEBUG=""
[ ! -f "$ICON_FIX" ] && ICON_FIX=""

# MAX Messenger
cat > "$DESKTOP_DIR/max-messenger.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Messenger
GenericName=Messenger
Comment=Запуск мессенджера MAX в Docker с полной изоляцией
Exec=${SCRIPT_DIR}/start-max.sh
Icon=${ICON_MAIN:-utilities-terminal}
Terminal=false
StartupNotify=true
StartupWMClass=max
Categories=Network;Chat;InstantMessaging;
Keywords=Messenger;MAX;
EOF

# MAX Debug Tool
cat > "$DESKTOP_DIR/max-debug-tool.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Debug Tool
Comment=Диагностика и отладка MAX Messenger
Exec=${SCRIPT_DIR}/max-debug.sh
Icon=${ICON_DEBUG:-utilities-terminal}
Terminal=true
Categories=Development;Debugger;
EOF

# MAX Fix Tool
cat > "$DESKTOP_DIR/max-fix-tool.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Fix Tool
Comment=Восстановление окружения после перезагрузки
Exec=${SCRIPT_DIR}/fix-after-reboot.sh
Icon=${ICON_FIX:-utilities-terminal}
Terminal=true
Categories=System;Utility;
EOF

# MAX Security Check
cat > "$DESKTOP_DIR/max-security-check.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MAX Security Check
Comment=Проверка безопасности и изоляции контейнера
Exec=${SCRIPT_DIR}/security-check.sh
Icon=${ICON_FIX:-utilities-terminal}
Terminal=true
Categories=System;Security;
EOF

update-desktop-database "$DESKTOP_DIR" 2>/dev/null
chmod +x "$DESKTOP_DIR"/max-*.desktop

echo "✓ Все десктопные ярлыки созданы"
echo "  - MAX Messenger"
echo "  - MAX Debug Tool"
echo "  - MAX Fix Tool"
echo "  - MAX Security Check"
