#!/bin/bash

# Raspberry Pi Kiosk Installer
# Voor Raspberry Pi OS Lite op Pi Zero 2 W

set -e  # Stop bij fouten

echo "=================================="
echo "Raspberry Pi Kiosk Installer"
echo "=================================="
echo ""

# Kleuren voor output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Vraag om URL
echo -e "${BLUE}Voer de URL in die je wilt weergeven:${NC}"
read -p "URL: " KIOSK_URL

if [ -z "$KIOSK_URL" ]; then
    echo "Geen URL ingevoerd. Script gestopt."
    exit 1
fi

echo ""
echo -e "${GREEN}[1/7] Systeem updaten...${NC}"
sudo apt update
sudo apt upgrade -y

echo ""
echo -e "${GREEN}[2/7] Installeren van minimale grafische omgeving...${NC}"
sudo apt install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox -y

echo ""
echo -e "${GREEN}[3/7] Installeren van Firefox ESR browser...${NC}"
sudo apt install --no-install-recommends firefox-esr -y

echo ""
echo -e "${GREEN}[4/7] Installeren van hulpprogramma's...${NC}"
sudo apt install unclutter -y

echo ""
echo -e "${GREEN}[5/7] Kiosk script aanmaken...${NC}"
cat > ~/kiosk.sh << EOF
#!/bin/bash
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.1 -root &
firefox-esr --kiosk ${KIOSK_URL}
EOF

chmod +x ~/kiosk.sh
echo "Kiosk script aangemaakt: ~/kiosk.sh"

echo ""
echo -e "${GREEN}[6/7] Autostart configureren...${NC}"

# .bash_profile aanmaken
cat > ~/.bash_profile << 'EOF'
if [ -z "$DISPLAY" ] && [ $(tty) = /dev/tty1 ]; then
    startx -- -nocursor
fi
EOF
echo ".bash_profile aangemaakt"

# .xinitrc aanmaken
cat > ~/.xinitrc << 'EOF'
#!/bin/bash
exec openbox-session &
~/kiosk.sh
EOF
chmod +x ~/.xinitrc
echo ".xinitrc aangemaakt"

echo ""
echo -e "${GREEN}[7/7] Auto-login configureren...${NC}"
sudo raspi-config nonint do_boot_behaviour B2

echo ""
echo -e "${GREEN}[Optioneel] GPU geheugen verhogen...${NC}"
if ! grep -q "gpu_mem=128" /boot/config.txt; then
    echo "gpu_mem=128" | sudo tee -a /boot/config.txt
    echo "GPU geheugen ingesteld op 128MB"
fi

echo ""
echo "=================================="
echo -e "${GREEN}Installatie voltooid!${NC}"
echo "=================================="
echo ""
echo "De kiosk toont: ${KIOSK_URL}"
echo ""
echo "Wil je nu herstarten? (j/n)"
read -p "> " REBOOT_CHOICE

if [ "$REBOOT_CHOICE" = "j" ] || [ "$REBOOT_CHOICE" = "J" ]; then
    echo "Herstarten..."
    sudo reboot
else
    echo "Herstart later handmatig met: sudo reboot"
fi
