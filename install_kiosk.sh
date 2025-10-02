cat > install_kiosk.sh << 'EOF'
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

  # Fallback voor sommige builds waar binnaam 'chromium' is
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
<!DOCTYPE html><html lang="nl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Digitale Lestimer</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:'Arial',sans-serif;background:#f3f4f6;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}.timer-container{background:white;border-radius:30px;padding:60px 40px;box-shadow:0 20px 60px rgba(0,0,0,.1);text-align:center;max-width:650px;width:100%;position:relative}.period-info{margin-bottom:60px}.date-info{font-size:18px;font-family:'Arial',sans-serif;color:#333;margin-bottom:55px;font-weight:normal}.period-name{font-size:48px;font-weight:bold;color:#333}.period-name.lesson{color:#dc2626}.period-name.break{color:#059669}.period-name.lunch{color:#ea580c}.timer-circle{position:relative;width:525px;height:525px;margin:0 auto 40px;background:linear-gradient(145deg,#f0f0f0,#cacaca);border-radius:50%;box-shadow:inset -10px -10px 20px rgba(255,255,255,.5),inset 10px 10px 20px rgba(0,0,0,.1),0 10px 20px rgba(0,0,0,.1)}.timer-inner{position:absolute;top:37px;left:37px;width:450px;height:450px;border-radius:50%;background:white;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:inset 5px 5px 10px rgba(0,0,0,.1),inset -5px -5px 10px rgba(255,255,255,.8)}.time-remaining{font-size:50px;font-weight:800;color:#333;margin-bottom:10px}.time-label{font-size:14px;color:#666;text-transform:uppercase;letter-spacing:1px}.analog-timer-svg{position:absolute;top:0;left:0;width:100%;height:100%;transform:rotate(-90deg)}.motivational-text{font-size:18px;color:#333;margin-top:60px;margin-bottom:60px;padding:15px;background:#f8f9fa;border-radius:15px}.motivational-text.break{background:#f0fdf4}.motivational-text.lunch{background:#fff7ed}.status-indicator{position:absolute;top:15px;right:15px;width:12px;height:12px;border-radius:50%;background:#6b7280;animation:pulse 2s infinite}.status-indicator.inactive{background:gray;animation:none}@keyframes pulse{0%{opacity:1}50%{opacity:.5}100%{opacity:1}}.student-subjects-list{margin-top:30px;padding:20px;background:#f8f9fa;border-radius:15px;box-shadow:inset 0 2px 4px rgba(0,0,0,.06);text-align:left;display:grid;grid-template-columns:1fr 1fr;gap:10px 20px;font-size:18px}.student-subjects-list p{color:#555;line-height:1.3;margin-bottom:5px}</style></head><body><div class="timer-container"><div id="timerContent"><div class="period-info"><div class="date-info" id="dateInfo"></div><div class="period-name" id="periodName"></div></div><div class="timer-circle"><svg class="analog-timer-svg" viewBox="0 0 280 280"><circle cx="140" cy="140" r="130" fill="white" stroke="#e5e7eb" stroke-width="5"/><path id="progressArc" fill="#dc2626" stroke="none"/><circle cx="140" cy="140" r="8" fill="#6b7280"/></svg><div class="timer-inner"><div class="time-remaining" id="timeRemaining">--:--</div></div></div><div class="motivational-text" id="motivationalText"></div><div class="student-subjects-list" id="studentSubjectsDisplay"></div></div></div><script>(script content...)</script></body></html>
HTML
    chown "${PI_USER}:${PI_USER}" "$INDEX_FILE"
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
  configure_hdmi_never_sleep
  disable_console_blank
  prepare_kiosk_files
  create_xinitrc
  create_systemd_service
  start_now
  summary
}

main "\$@"
EOF
