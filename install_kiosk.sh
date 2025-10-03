#!/bin/bash

# =================================================================
# Raspberry Pi Kiosk Installer (Verbeterde Versie)
# Voor Raspberry Pi OS Lite op Pi Zero 2 W en andere modellen
#
# Verbeteringen:
# - Gebruikt ~/.profile voor betrouwbaardere autostart.
# - Voegt een pauze toe om race conditions bij opstarten te voorkomen.
# - Herstart Firefox automatisch als deze crasht.
# =================================================================

set -e  # Stop direct bij fouten

# Kleuren voor output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Raspberry Pi Kiosk Installer (Verbeterd)"
echo "=========================================="
echo ""

# Vraag om URL
echo -e "${BLUE}Voer de URL in die je wilt weergeven in kiosk modus:${NC}"
read -p "URL: " KIOSK_URL

if [ -z "$KIOSK_URL" ]; then
    echo "Fout: Geen URL ingevoerd. Script gestopt."
    exit 1
fi

echo ""
echo -e "${GREEN}[1/7] Systeem updaten...${NC}"
sudo apt-get update
sudo apt-get upgrade -y

echo ""
echo -e "${GREEN}[2/7] Installeren van minimale grafische omgeving...${NC}"
sudo apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox -y

echo ""
echo -e "${GREEN}[3/7] Installeren van Firefox ESR browser...${NC}"
sudo apt-get install --no-install-recommends firefox-esr -y

echo ""
echo -e "${GREEN}[4/7] Installeren van hulpprogramma's (muiscursor verbergen)...${NC}"
sudo apt-get install --no-install-recommends unclutter -y

echo ""
echo -e "${GREEN}[5/7] Kiosk script aanmaken...${NC}"
# Dit script bevat nu een 'while true' lus om Firefox te herstarten bij een crash.
cat > ~/kiosk.sh << EOF
#!/bin/bash

# Schakel screensaver en power management van het scherm uit
xset s off
xset -dpms
xset s noblank

# Verberg de muiscursor na 1 seconde inactiviteit
unclutter -idle 1 -root &

# Geef Openbox de tijd om volledig te starten voordat de browser wordt geladen
sleep 5

# Start Firefox in een oneindige lus. Als de browser crasht, start hij opnieuw.
while true; do
  firefox-esr --kiosk "${KIOSK_URL}"
  echo "Firefox is afgesloten. Herstarten over 10 seconden..."
  sleep 10
done
EOF

chmod +x ~/kiosk.sh
echo "Kiosk script aangemaakt: ~/kiosk.sh"

echo ""
echo -e "${GREEN}[6/7] Autostart configureren...${NC}"

# .xinitrc aanmaken om de kiosk te starten binnen de grafische sessie
cat > ~/.xinitrc << 'EOF'
#!/bin/bash
# Start de Openbox window manager op de achtergrond
exec openbox-session &
# Voer ons kiosk script uit
~/kiosk.sh
EOF

chmod +x ~/.xinitrc
echo ".xinitrc aangemaakt."

# Autostart logica toevoegen aan ~/.profile voor betrouwbaarheid
# Dit start de grafische omgeving (startx) automatisch na het inloggen op tty1
AUTOSTART_LOGIC='if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then startx -- -nocursor; fi'
if ! grep -qF -- "$AUTOSTART_LOGIC" ~/.profile; then
    echo "$AUTOSTART_LOGIC" >> ~/.profile
    echo "Autostart logica toegevoegd aan ~/.profile."
else
    echo "Autostart logica was al aanwezig in ~/.profile."
fi

echo ""
echo -e "${GREEN}[7/7] Auto-login configureren...${NC}"
# B2 staat voor "Boot to console, automatically logged in as 'pi' user"
# Vervang 'pi' door je daadwerkelijke gebruikersnaam indien anders.
if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
    echo "Auto-login lijkt al geconfigureerd te zijn."
else
    sudo raspi-config nonint do_boot_behaviour B2
fi

echo ""
echo -e "${GREEN}[Optioneel] GPU geheugen instellen...${NC}"
if ! grep -q "gpu_mem=128" /boot/config.txt; then
    echo "gpu_mem=128" | sudo tee -a /boot/firmware/config.txt > /dev/null
    echo "GPU geheugen ingesteld op 128MB."
else
    echo "GPU geheugen stond al op 128MB of meer."
fi

echo ""
echo "=================================="
echo -e "${GREEN}Installatie voltooid!${NC}"
echo "=================================="
echo ""
echo "De kiosk zal de volgende URL tonen: ${KIOSK_URL}"
echo ""
echo "Het is aan te raden om nu te herstarten om de wijzigingen door te voeren."
read -p "Wil je nu herstarten? (j/n) " REBOOT_CHOICE

if [[ "$REBOOT_CHOICE" =~ ^[Jj]$ ]]; then
    echo "Herstarten..."
    sudo reboot
else
    echo "Oké. Herstart later handmatig met: sudo reboot"
fi
