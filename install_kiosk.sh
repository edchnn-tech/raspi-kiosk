#!/usr/bin/env bash
set -euo pipefail

# === Instellingen ===
PI_USER="${PI_USER:-admin}" # pas aan als je andere gebruikersnaam hebt
KIOSK_DIR="/home/${PI_USER}/kiosk"
INDEX_FILE="${KIOSK_DIR}/index.html"
XINITRC="/home/${PI_USER}/.xinitrc"
OPENBOX_DIR="/home/${PI_USER}/.config/openbox"
SERVICE_FILE="/etc/systemd/system/kiosk.service"
CONFIG_TXT="/boot/firmware/config.txt" # Raspberry Pi OS Bookworm
CMDLINE_TXT="/boot/firmware/cmdline.txt"
REFLECT="${REFLECT:-x}" # 'x' = links↔rechts spiegelen; 'y' = ondersteboven
CHROMIUM_BIN="chromium-browser"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this script with sudo: sudo $0"; exit 1
  fi
}

replace_or_append_kv() {
  local key="$1" val="$2" file="$3"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|g" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

ensure_user() {
  if ! id "$PI_USER" &>/dev/null; then
    echo "Gebruiker '$PI_USER' bestaat niet. Pas PI_USER= aan bovenin het script."
    exit 1
  fi
}

install_packages() {
  apt update
  apt full-upgrade -y
  apt install -y --no-install-recommends \
    xserver-xorg x11-xserver-utils xinit openbox unclutter xdotool \
    chromium-browser || true

  if ! command -v chromium-browser &>/dev/null; then
    apt install -y chromium
    CHROMIUM_BIN="chromium"
  fi
}

configure_hdmi_never_sleep() {
  touch "$CONFIG_TXT"
  replace_or_append_kv "hdmi_force_hotplug" "1" "$CONFIG_TXT"
  replace_or_append_kv "hdmi_drive" "2" "$CONFIG_TXT"
  replace_or_append_kv "disable_overscan" "1" "$CONFIG_TXT"
}

disable_console_blank() {
  if [[ -f "$CMDLINE_TXT" ]] && ! grep -q "consoleblank=0" "$CMDLINE_TXT"; then
    sed -i 's/$/ consoleblank=0/' "$CMDLINE_TXT"
  fi
}

prepare_kiosk_files() {
  mkdir -p "$KIOSK_DIR"
  chown -R "${PI_USER}:${PI_USER}" "$KIOSK_DIR"

  if [[ ! -f "$INDEX_FILE" ]]; then
    cat > "$INDEX_FILE" <<'HTML'
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kiosk</title>
</head>
<body>
    <h1>Installatie Succesvol</h1>
    <p>Je kunt nu de volledige HTML code van je timer plakken in het bestand: /home/admin/kiosk/index.html</p>
</body>
</html>
HTML
  fi

  mkdir -p "$OPENBOX_DIR"
  echo '# leeg' > "${OPENBOX_DIR}/autostart"
  chown -R "${PI_USER}:${PI_USER}" "/home/${PI_USER}/.config"
}

create_xinitrc() {
  cat > "$XINITRC" <<EOF2
#!/bin/sh
unclutter -idle 0.1 -root &
xset -dpms
xset s off
xset s noblank
OUT="\$(xrandr | awk '/ connected/{print \$1; exit}')"
if [ -n "\$OUT" ]; then
  xrandr --output "\$OUT" --reflect ${REFLECT} || true
fi
exec ${CHROMIUM_BIN} \\
  --noerrdialogs --disable-infobars \\
  --kiosk "file://${INDEX_FILE}"
EOF2
  chown "${PI_USER}:${PI_USER}" "$XINITRC"
  chmod +x "$XINITRC"
}

create_systemd_service() {
  cat > "$SERVICE_FILE" <<EOF3
[Unit]
Description=Kiosk (Chromium fullscreen)
After=network-online.target
[Service]
User=${PI_USER}
Environment=DISPLAY=:0
WorkingDirectory=/home/${PI_USER}
ExecStart=/usr/bin/startx
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF3
  systemctl daemon-reload
  systemctl enable kiosk.service
}

start_now() {
  systemctl restart kiosk.service || systemctl start kiosk.service
}

summary() {
  echo "========================================"
  echo " Klaar!"
  echo " Service status: systemctl status kiosk.service"
  echo " Reboot aanbevolen: sudo reboot"
  echo "========================================"
}

main() {
  require_root
  ensure_user
  install_packages
