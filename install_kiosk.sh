#!/usr/bin/env bash
set -euo pipefail

# === Instellingen ===
PI_USER="${PI_USER:-admin}" # pas aan als je andere gebruikersnaam hebt
KIOSK_DIR="/home/${PI_USER}/kiosk"
INDEX_FILE="${KIOSK_DIR}/index.html"
XINITRC="/home/${PI_USER}/.xinitrc"
OPENBOX_DIR="/home/${PI_USER}/.config/openbox"
SERVICE_FILE="/etc/systemd/system/kiosk.service"
CONFIG_TXT="/boot/firmware/config.txt" # Voor Raspberry Pi OS Bookworm
CMDLINE_TXT="/boot/firmware/cmdline.txt"
REFLECT="${REFLECT:-x}" # 'x' = links↔rechts spiegelen; 'y' = ondersteboven
CHROMIUM_BIN="chromium-browser"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Dit script moet met sudo worden uitgevoerd: sudo $0"; exit 1
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
  echo "--- Software installeren en updaten ---"
  apt update
  apt full-upgrade -y
  apt install -y --no-install-recommends \
    xserver-xorg x11-xserver-utils xinit openbox unclutter xdotool \
    chromium-browser || true

  # Fallback voor builds waar de browser 'chromium' heet
  if ! command -v chromium-browser &>/dev/null; then
    apt install -y chromium
    CHROMIUM_BIN="chromium"
  fi
}

configure_hdmi_never_sleep() {
  echo "--- HDMI-instellingen configureren (voorkomt slaapstand) ---"
  touch "$CONFIG_TXT"
  replace_or_append_kv "hdmi_force_hotplug" "1" "$CONFIG_TXT"
  replace_or_append_kv "hdmi_drive" "2" "$CONFIG_TXT"
  replace_or_append_kv "disable_overscan" "1" "$CONFIG_TXT"
}

disable_console_blank() {
  echo "--- Console screensaver uitschakelen ---"
  if [[ -f "$CMDLINE_TXT" ]] && ! grep -q "consoleblank=0" "$CMDLINE_TXT"; then
    sed -i 's/$/ consoleblank=0/' "$CMDLINE_TXT"
  fi
}

prepare_kiosk_files() {
  echo "--- Kiosk-bestanden voorbereiden ---"
  mkdir -p "$KIOSK_DIR"
  chown -R "${PI_USER}:${PI_USER}" "$KIOSK_DIR"

  # Maak automatisch een mini index.html bestand aan
  cat > "$INDEX_FILE" <<HTML
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Kiosk Actief</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            text-align: center;
            height: 100vh;
            margin: 0;
            background-color: #282c34;
            color: white;
        }
        div {
            border: 2px solid #61dafb;
            padding: 2rem 4rem;
            border-radius: 12px;
        }
        h1 {
            font-size: 3em;
            color: #61dafb;
        }
        code {
            background-color: #444;
            padding: 0.2em 0.4em;
            border-radius: 4px;
            color: #bfa3c6;
        }
    </style>
</head>
<body>
    <div>
        <h1>Kiosk Modus Actief</h1>
        <p>Dit scherm is succesvol opgestart door het installatiescript.</p>
        <p>Je kunt dit HTML-bestand aanpassen op de Pi in: <code>${INDEX_FILE}</code></p>
    </div>
</body>
</html>
HTML

  chown "${PI_USER}:${PI_USER}" "$INDEX_FILE"
  echo "Testpagina succesvol aangemaakt in ${INDEX_FILE}"

  mkdir -p "$OPENBOX_DIR"
  echo '# leeg' > "${OPENBOX_DIR}/autostart"
  chown -R "${PI_USER}:${PI_USER}" "/home/${PI_USER}/.config"
}

create_xinitrc() {
  echo "--- .xinitrc-bestand aanmaken voor autostart browser ---"
  cat > "$XINITRC" <<EOF2
#!/bin/sh
# Verberg muiscursor na inactiviteit
unclutter -idle 0.1 -root &

# Schakel screensaver en DPMS (energiebeheer voor monitor) uit
xset -dpms
xset s off
xset s noblank

# Detecteer de actieve video-uitgang en pas spiegeling toe
OUT="\$(xrandr | awk '/ connected/{print \$1; exit}')"
if [ -n "\$OUT" ]; then
  xrandr --output "\$OUT" --reflect ${REFLECT} || true
fi

# Start Chromium in kiosk modus
exec ${CHROMIUM_BIN} \\
  --noerrdialogs --disable-infobars \\
  --kiosk "file://${INDEX_FILE}"
EOF2
  chown "${PI_USER}:${PI_USER}" "$XINITRC"
  chmod +x "$XINITRC"
}

create_systemd_service() {
  echo "--- Systemd service (kiosk.service) aanmaken ---"
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
  sudo systemctl daemon-reload
  sudo systemctl enable kiosk.service
  echo "Service 'kiosk.service' is geactiveerd."
}

start_now() {
  echo "--- Kiosk service herstarten ---"
  sudo systemctl restart kiosk.service || sudo systemctl start kiosk.service
}

summary() {
  echo
  echo "======================================================"
  echo " INSTALLATIE VOLTOOID!"
  echo "======================================================"
  echo " De kiosk-modus zou nu moeten opstarten."
  echo " Als er iets misgaat, controleer de status met:"
  echo "   systemctl status kiosk.service"
  echo
  echo " Een herstart wordt aanbevolen om alle boot-instellingen"
  echo " correct toe te passen:"
  echo "   sudo reboot"
  echo "======================================================"
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

main "$@"
