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
   
    echo '<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Digitale Lestimer voor Klaslokalen</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Arial', sans-serif;
            background: #f3f4f6;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }

        .timer-container {
            background: white;
            border-radius: 30px;
            padding: 60px 40px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.1);
            text-align: center;
            max-width: 650px;
            width: 100%;
            position: relative;
        }

        .period-info {
            margin-bottom: 60px;
        }

        .date-info {
            font-size: 18px;
            font-family: 'Arial', sans-serif;
            color: #333;
            margin-bottom: 55px;
            font-weight: normal;
        }

        .period-name {
            font-size: 48px;
            font-weight: bold;
            color: #333;
        }

        .period-name.lesson {
            color: #dc2626;
        }

        .period-name.break {
            color: #059669;
        }

        .period-name.lunch {
            color: #ea580c;
        }

        .timer-circle {
            position: relative;
            width: 525px;
            height: 525px;
            margin: 0 auto 40px;
            background: linear-gradient(145deg, #f0f0f0, #cacaca);
            border-radius: 50%;
            box-shadow: 
                inset -10px -10px 20px rgba(255, 255, 255, 0.5),
                inset 10px 10px 20px rgba(0, 0, 0, 0.1),
                0 10px 20px rgba(0, 0, 0, 0.1);
        }

        .timer-inner {
            position: absolute;
            top: 37px;
            left: 37px;
            width: 450px;
            height: 450px;
            border-radius: 50%;
            background: white;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            box-shadow: 
                inset 5px 5px 10px rgba(0, 0, 0, 0.1),
                inset -5px -5px 10px rgba(255, 255, 255, 0.8);
        }

        .time-remaining {
            font-size: 50px;
            font-weight: 800;
            color: #333;
            /**font-family: 'Courier New', monospace;**/
            margin-bottom: 10px;
        }

        .time-label {
            font-size: 14px;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .progress-ring {
        }

        .analog-timer-svg {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            transform: rotate(-90deg);
        }

        .motivational-text {
            font-size: 18px;
            color: #333;
            margin-top: 60px;
            margin-bottom: 60px;
            padding: 15px;
            background: #f8f9fa;
            border-radius: 15px;
        }

        .motivational-text.break {
            border-left-color: #6b7280;
            background: #f0fdf4;
        }

        .motivational-text.lunch {
            border-left-color: #6b7280;
            background: #fff7ed;
        }

        .status-indicator {
            position: absolute;
            top: 15px;
            right: 15px;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #6b7280;
            animation: pulse 2s infinite;
        }

        .status-indicator.break {
            background: #6b7280;
        }

        .status-indicator.lunch {
            background: #6b7280;
        }

        .status-indicator.inactive {
            background: #gray;
            animation: none;
        }

        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }

        .no-period {
            color: #666;
            font-size: 18px;
            padding: 40px;
        }

        .student-subjects-list {
            margin-top: 30px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 15px;
            box-shadow: inset 0 2px 4px rgba(0,0,0,0.06);
            text-align: center;
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            font-size: 22px;
        }

        .student-subjects-list h3 {
            color: #333;
            margin-bottom: 10px;
            font-size: 18px;
            font-weight: bold;
            grid-column: 1 / -1;
        }

        .student-subjects-list p {
            color: #555;
            line-height: 1.3;
            margin-bottom: 5px;
            font-size: 18px;
        }

        @media (max-width: 768px) {
            .student-subjects-list {
                grid-template-columns: 1fr;
            }

            .student-subjects-list {
                grid-template-columns: 1fr;
            }

            .timer-container {
                padding: 30px 20px;
            }

            .timer-circle {
                width: 360px;
                height: 360px;
            }

            .timer-inner {
                width: 300px;
                height: 300px;
                top: 30px;
                left: 30px;
            }

            .progress-ring {
                width: 220px;
                height: 220px;
            }

            .time-remaining {
                font-size: 36px;
            }

            .period-name {
                font-size: 24px;
            }
        }
    </style>
</head>
<body>
    <div class="timer-container">
        <div class="status-indicator" id="statusIndicator"></div>
        
        <div id="timerContent">
            <div class="period-info">
                <div class="date-info" id="dateInfo">Het is vandaag...</div>
                <div class="period-name" id="periodName">Wachten...</div>
            </div>

            <div class="timer-circle">
                <svg class="analog-timer-svg" viewBox="0 0 280 280" id="analogTimerSvg">
                    <!-- Witte achtergrond cirkel -->
                    <circle cx="140" cy="140" r="130" fill="white" stroke="#e5e7eb" stroke-width="5"/>
                    <!-- Rode gevulde boog voor resterende tijd -->
                    <path id="progressArc" fill="#dc2626" stroke="none"/>
                    <!-- Centraal punt -->
                    <circle cx="140" cy="140" r="8" fill="#6b7280"/>
                </svg>
                <div class="timer-inner">
                    <div class="time-remaining" id="timeRemaining">--:--</div>
                    <div class="time-label"></div>
                </div>
            </div>

            <div class="motivational-text" id="motivationalText">
                Welkom bij de digitale lestimer!
            </div>

            <div class="student-subjects-list" id="studentSubjectsDisplay">
                <!-- Hier komen de leerlingvakken te staan -->
            </div>
        </div>
    </div>

    <script>
        // SIMULATIE MODUS - Zet op true om het 1e uur te simuleren
        const SIMULATION_MODE = true
          ;
        const SIMULATED_START_TIME = "08:02"; // Start simulatie op dit tijdstip
        let simulationStartRealTime = null; // Wanneer de simulatie begon (echte tijd)

        const schedule = [
            {
                name: "Het 1e uur",
                startTime: "08:30:45",
                endTime: "09:15:45",
                type: "lesson",
                motivationalText: "Succes, zet hem op vandaag! 💪"
            },
            {
                name: "Pauze",
                startTime: "09:15:45",
                endTime: "09:25:45",
                type: "break",
                motivationalText: "10 minuten pauze! Even bijkomen. ☕"
            },
            {
                name: "Het 2e uur",
                startTime: "09:25:45",
                endTime: "10:00:45",
                type: "lesson",
                motivationalText: "Succes dit 2e uur alweer! 🚀"
            },
            {
                name: "Pauze",
                startTime: "10:00:45",
                endTime: "10:10:45",
                type: "break",
                motivationalText: "10 minuten pauze! Stretch jezelf even. 🤸"
            },
            {
                name: "Het 3e uur",
                startTime: "10:10:45",
                endTime: "10:45:45",
                type: "lesson",
                motivationalText: "Het 3e uur alweer, bijna tijd om te eten! 🎯"
            },
            {
                name: "Eetpauze",
                startTime: "10:45:45",
                endTime: "11:05:45",
                type: "lunch",
                motivationalText: "Eetsmakelijk! Geniet van je pauze! 🍽️"
            },
            {
                name: "Pauze",
                startTime: "11:05:45",
                endTime: "11:25:45",
                type: "break",
                motivationalText: "Nog even pauze! Bijna weer aan de slag. 😊"
            },
            {
                name: "Het 4e uur",
                startTime: "11:30:45",
                endTime: "12:05:45",
                type: "lesson",
                motivationalText: "Fantastisch! De helft van de dag is al voorbij! 🌟"
            },
            {
                name: "Pauze",
                startTime: "12:05:45",
                endTime: "12:15:45",
                type: "break",
                motivationalText: "10 minuten pauze! 👏"
            },
            {
                name: "Het 5e uur",
                startTime: "12:15:45",
                endTime: "12:50:45",
                type: "lesson",
                motivationalText: "Het 5e uur is weer begonnen! 🏁"
            },
            {
                name: "Pauze",
                startTime: "12:50:45",
                endTime: "13:00:45",
                type: "break",
                motivationalText: "10 minuten pauze! De eindstreep komt in zicht! 👀"
            },
            {
                name: "Het 6e uur",
                startTime: "13:00:45",
                endTime: "13:35:45",
                type: "lesson",
                motivationalText: "Het 6e uur, zet hem op! ✨"
            },
            {
                name: "Pauze",
                startTime: "13:35:45",
                endTime: "13:45:45",
                type: "break",
                motivationalText: "10 minuten pauze! 🏃"
            },
            {
                name: "Het 7e uur",
                startTime: "13:45:45",
                endTime: "14:20:45",
                type: "lesson",
                motivationalText: "Één na laatste uurtje alweer! 🎉"
            },
            {
                name: "Pauze",
                startTime: "14:20:45",
                endTime: "14:45:45",
                type: "break",
                motivationalText: "Nog een pauze! Bijna klaar voor vandaag! 💪"
            },
            {
                name: "Het 8e uur",
                startTime: "14:45:45",
                endTime: "15:30:45",
                type: "lesson",
                motivationalText: "Het allerlaatste uur! 🏆"
            }
        ];

      
        // Mockdata voor 12 leerlingen en hun vakken
        const students = [
            {
                name: "Tygo",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "GD",
                        "Het 3e uur": "NE",
                        "Het 4e uur": "BWI",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "EN",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "NASK",
                        "Het 3e uur": "NE",
                        "Het 4e uur": "EN",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "BWI",
                        "Het 8e uur": "BWI"
                    },
                    "woensdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "NASK",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "WI",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "Qompas",
                        "Het 6e uur": "WI",
                        "Het 7e uur": "NE",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "Stage",
                        "Het 2e uur": "Stage",
                        "Het 3e uur": "Stage",
                        "Het 4e uur": "Stage",
                        "Het 5e uur": "Stage",
                        "Het 6e uur": "Stage",
                        "Het 7e uur": "Stage",
                        "Het 8e uur": "Stage"
                    }
                }
            },
            {
                name: "Thomas",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "EC",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "EN",
                        "Het 2e uur": "NASK",
                        "Het 3e uur": "WI",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "Qompas",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "GS",
                        "Het 2e uur": "BIO",
                        "Het 3e uur": "GD",
                        "Het 4e uur": "EN",
                        "Het 5e uur": "WI",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "BIO",
                        "Het 2e uur": "GS",
                        "Het 3e uur": "WI",
                        "Het 4e uur": "Duits",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "EC",
                        "Het 2e uur": "Duits",
                        "Het 3e uur": "NE",
                        "Het 4e uur": "NASK",
                        "Het 5e uur": "--",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Levi",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "BIO",
                        "Het 3e uur": "GD",
                        "Het 4e uur": "EC",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "--",
                        "Het 3e uur": "WI",
                        "Het 4e uur": "EN",
                        "Het 5e uur": "EC",
                        "Het 6e uur": "Z&W",
                        "Het 7e uur": "Z&W",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "GD",
                        "Het 2e uur": "Z&W",
                        "Het 3e uur": "Z&W",
                        "Het 4e uur": "BIO",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "EN",
                        "Het 3e uur": "EC",
                        "Het 4e uur": "BIO",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "Qompas",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "BIO",
                        "Het 2e uur": "Z&W",
                        "Het 3e uur": "WI",
                        "Het 4e uur": "EN",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "EC",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Jonah",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "Z&W",
                        "Het 2e uur": "Z&W",
                        "Het 3e uur": "Z&W",
                        "Het 4e uur": "NE",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "BIO",
                        "Het 7e uur": "EN",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "BIO",
                        "Het 2e uur": "Z&W",
                        "Het 3e uur": "Z&W",
                        "Het 4e uur": "Z&W",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "WI",
                        "Het 7e uur": "MA",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "GD",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "Z&W",
                        "Het 5e uur": "Z&W",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "WI",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "BIO",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "Z&W",
                        "Het 5e uur": "Z&W",
                        "Het 6e uur": "Z&W",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "Z&W",
                        "Het 2e uur": "Z&W",
                        "Het 3e uur": "Z&W",
                        "Het 4e uur": "MA",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "WI",
                        "Het 7e uur": "GD",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Nathan S",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "NE",
                        "Het 2e uur": "EN",
                        "Het 3e uur": "AK",
                        "Het 4e uur": "REK",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "NE",
                        "Het 2e uur": "Qompas",
                        "Het 3e uur": "EC",
                        "Het 4e uur": "MA",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "GS",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "MA",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "EC",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "AK",
                        "Het 2e uur": "EN",
                        "Het 3e uur": "GS",
                        "Het 4e uur": "BIO",
                        "Het 5e uur": "--",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "GD",
                        "Het 4e uur": "BIO",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Chibueze",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "E&O",
                        "Het 2e uur": "E&O",
                        "Het 3e uur": "E&O",
                        "Het 4e uur": "NE",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "EC",
                        "Het 7e uur": "E&O",
                        "Het 8e uur": "E&O"
                    },
                    "dinsdag": {
                        "Het 1e uur": "MA",
                        "Het 2e uur": "E&O",
                        "Het 3e uur": "E&O",
                        "Het 4e uur": "E&O",
                        "Het 5e uur": "WI",
                        "Het 6e uur": "Qompas",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "EC",
                        "Het 2e uur": "GD",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "E&O",
                        "Het 5e uur": "E&O",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "NE",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "MA",
                        "Het 2e uur": "WI",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "E&O",
                        "Het 5e uur": "E&O",
                        "Het 6e uur": "E&O",
                        "Het 7e uur": "NE",
                        "Het 8e uur": "GD"
                    },
                    "vrijdag": {
                        "Het 1e uur": "E&O",
                        "Het 2e uur": "E&O",
                        "Het 3e uur": "E&O",
                        "Het 4e uur": "EC",
                        "Het 5e uur": "WI",
                        "Het 6e uur": "EN",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Hendrik",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "NE",
                        "Het 2e uur": "EN",
                        "Het 3e uur": "NA",
                        "Het 4e uur": "WI",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "EC",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "NE",
                        "Het 2e uur": "Qompas",
                        "Het 3e uur": "NA",
                        "Het 4e uur": "WI",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "HW",
                        "Het 3e uur": "MA",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "BWI",
                        "Het 8e uur": "BWI"
                    },
                    "donderdag": {
                        "Het 1e uur": "AK",
                        "Het 2e uur": "EN",
                        "Het 3e uur": "NA",
                        "Het 4e uur": "MA",
                        "Het 5e uur": "EC",
                        "Het 6e uur": "HW",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "AK",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "GD",
                        "Het 4e uur": "WI",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Mart",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "EC",
                        "Het 4e uur": "E&O",
                        "Het 5e uur": "E&O",
                        "Het 6e uur": "E&O",
                        "Het 7e uur": "EC",
                        "Het 8e uur": "DU"
                    },
                    "dinsdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "DU",
                        "Het 4e uur": "Qompas",
                        "Het 5e uur": "E&O",
                        "Het 6e uur": "E&O",
                        "Het 7e uur": "EN",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "E&O",
                        "Het 2e uur": "E&O",
                        "Het 3e uur": "E&O",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "DU",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "DU",
                        "Het 2e uur": "E&O",
                        "Het 3e uur": "E&O",
                        "Het 4e uur": "NE",
                        "Het 5e uur": "GD",
                        "Het 6e uur": "EN",
                        "Het 7e uur": "EC",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "Stage",
                        "Het 2e uur": "Stage",
                        "Het 3e uur": "Stage",
                        "Het 4e uur": "Stage",
                        "Het 5e uur": "Stage",
                        "Het 6e uur": "Stage",
                        "Het 7e uur": "Stage",
                        "Het 8e uur": "Stage"
                    }
                }
            },
            {
                name: "Jurrian",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "GD",
                        "Het 3e uur": "NE",
                        "Het 4e uur": "BWI",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "EN",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "WI",
                        "Het 2e uur": "NASK",
                        "Het 3e uur": "NE",
                        "Het 4e uur": "EN",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "BWI",
                        "Het 8e uur": "BWI"
                    },
                    "woensdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "NASK",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "WI",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "Qompas",
                        "Het 6e uur": "WI",
                        "Het 7e uur": "NE",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "Stage",
                        "Het 2e uur": "Stage ",
                        "Het 3e uur": "Stage ",
                        "Het 4e uur": "Stage",
                        "Het 5e uur": "Stage",
                        "Het 6e uur": "Stage",
                        "Het 7e uur": "Stage",
                        "Het 8e uur": "Stage"
                    }
                }
            },
            {
                name: "Thieme",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "LO",
                        "Het 6e uur": "MA",
                        "Het 7e uur": "BWI",
                        "Het 8e uur": "BWI"
                    },
                    "dinsdag": {
                        "Het 1e uur": "EN",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "BWI",
                        "Het 5e uur": "Qompas",
                        "Het 6e uur": "WI",
                        "Het 7e uur": "NASK",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "NE",
                        "Het 2e uur": "WI",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "BWI",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "NASK",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "NE",
                        "Het 2e uur": "MA",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "BWI",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "GD",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "WI",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "NASK",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Joah",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "--",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "EC",
                        "Het 5e uur": "WI",
                        "Het 6e uur": "NE",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "--",
                        "Het 3e uur": "WI",
                        "Het 4e uur": "GS",
                        "Het 5e uur": "NA",
                        "Het 6e uur": "EN",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "woensdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "--",
                        "Het 3e uur": "GD",
                        "Het 4e uur": "BI",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "GS",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "--",
                        "Het 3e uur": "--",
                        "Het 4e uur": "--",
                        "Het 5e uur": "--",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "--",
                        "Het 2e uur": "--",
                        "Het 3e uur": "BI",
                        "Het 4e uur": "NA",
                        "Het 5e uur": "DU",
                        "Het 6e uur": "EC",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            },
            {
                name: "Nathan V",
                schedule: {
                    "maandag": {
                        "Het 1e uur": "NA",
                        "Het 2e uur": "WI",
                        "Het 3e uur": "NE",
                        "Het 4e uur": "BWI",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "dinsdag": {
                        "Het 1e uur": "Qompas",
                        "Het 2e uur": "GD",
                        "Het 3e uur": "EN",
                        "Het 4e uur": "WI",
                        "Het 5e uur": "BWI",
                        "Het 6e uur": "BWI",
                        "Het 7e uur": "BWI",
                        "Het 8e uur": "BWI"
                    },
                    "woensdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "NA",
                        "Het 5e uur": "NE",
                        "Het 6e uur": "LO",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "donderdag": {
                        "Het 1e uur": "BWI",
                        "Het 2e uur": "BWI",
                        "Het 3e uur": "BWI",
                        "Het 4e uur": "NA",
                        "Het 5e uur": "EN",
                        "Het 6e uur": "WI",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    },
                    "vrijdag": {
                        "Het 1e uur": "EN",
                        "Het 2e uur": "NE",
                        "Het 3e uur": "WI",
                        "Het 4e uur": "GD",
                        "Het 5e uur": "--",
                        "Het 6e uur": "--",
                        "Het 7e uur": "--",
                        "Het 8e uur": "--"
                    }
                }
            }
        ];


        function timeToSeconds(timeStr) {
            const parts = timeStr.split(':').map(Number);
            const hours = parts[0];
            const minutes = parts[1];
            const seconds = parts[2] || 0;
            return hours * 3600 + minutes * 60 + seconds;
        }

        function getCurrentPeriod(now) {
            const currentSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();

            console.log('Current time:', now.getHours() + ':' + now.getMinutes().toString().padStart(2, '0') + ':' + now.getSeconds().toString().padStart(2, '0'));
            console.log('Current seconds:', currentSeconds);

            for (const period of schedule) {
                const startSeconds = timeToSeconds(period.startTime);
                const endSeconds = timeToSeconds(period.endTime);

                console.log(`Checking ${period.name}: ${startSeconds}-${endSeconds} seconds`);

                if (currentSeconds >= startSeconds && currentSeconds < endSeconds) {
                    console.log('Found current period:', period.name);
                    return period;
                }
            }
            console.log('No current period found');
            return null;
        }

        function isLastMinuteBeforeLesson(currentPeriod, now) {
            if (!currentPeriod || currentPeriod.type === 'lesson') {
                return false; // Niet in een pauze/lunch, of al in een les
            }

            const currentSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
            const endSeconds = timeToSeconds(currentPeriod.endTime);
            const timeUntilEnd = endSeconds - currentSeconds;

            // Check of we in de laatste minuut zitten (60 seconden)
            if (timeUntilEnd <= 60 && timeUntilEnd > 0) {
                // Zoek het volgende item in het schema
                const currentIndex = schedule.findIndex(p => p === currentPeriod);
                if (currentIndex >= 0 && currentIndex < schedule.length - 1) {
                    const nextPeriod = schedule[currentIndex + 1];
                    // Check of het volgende item een lesuur is
                    return nextPeriod.type === 'lesson';
                }
            }

            return false;
        }
        function getUpcomingLesson(now) {
            const currentSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();

            // Zoek naar het volgende lesuur (niet pauze of lunch)
            for (const period of schedule) {
                const startSeconds = timeToSeconds(period.startTime);

                // Check of dit een lesuur is en of het binnen 60 seconden begint
                if (period.type === 'lesson' &&
                    currentSeconds < startSeconds &&
                    startSeconds - currentSeconds <= 60) {
                    return period;
                }
            }
            return null;
        }
        function calculateTimeRemaining(period, now) {
            const currentSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
            const startSeconds = timeToSeconds(period.startTime);
            const endSeconds = timeToSeconds(period.endTime);

            const totalDuration = endSeconds - startSeconds;
            const elapsed = currentSeconds - startSeconds;
            const remaining = endSeconds - currentSeconds;

            const progressPercent = Math.min(100, Math.max(0, (elapsed / totalDuration) * 100));

            const remainingMinutes = Math.floor(remaining / 60);
            const remainingSeconds = Math.floor(remaining % 60);

            // Format time as "X min" instead of "MM:SS"
            let timeDisplay;
            if (remainingMinutes > 0) {
                timeDisplay = `${remainingMinutes} min`;
            } else {
                timeDisplay = `${remainingSeconds}s`;
            }

            return {
                remaining: timeDisplay,
                progress: progressPercent
            };
        }

        function getSimulatedTime() {
            if (!SIMULATION_MODE) return new Date();
            
            // Initialiseer simulatie start tijd als dit de eerste keer is
            if (simulationStartRealTime === null) {
                simulationStartRealTime = new Date();
            }
            
            // Bereken hoeveel tijd er verstreken is sinds simulatie start
            const realTimeElapsed = new Date().getTime() - simulationStartRealTime.getTime();
            
            // Start met de gesimuleerde tijd en tel de verstreken tijd erbij op
            const [hours, minutes] = SIMULATED_START_TIME.split(':').map(Number);
            const now = new Date();
            // Zet de datum op maandag (dag 1)
            const today = new Date();
            const dayOfWeek = today.getDay(); // 0 = zondag, 1 = maandag, etc.
            const daysUntilMonday = dayOfWeek === 0 ? 1 : (8 - dayOfWeek) % 7;
            now.setDate(today.getDate() + daysUntilMonday);
            now.setHours(hours, minutes, 0, 0);
            
            // Voeg de verstreken tijd toe aan de gesimuleerde starttijd
            now.setTime(now.getTime() + realTimeElapsed);
            
            return now;
        }

        function updateDisplay() {
            const now = SIMULATION_MODE ? getSimulatedTime() : new Date();
            const periodNameElement = document.getElementById('periodName');
            const dateInfoElement = document.getElementById('dateInfo');
            const timeRemainingElement = document.getElementById('timeRemaining');
            const motivationalTextElement = document.getElementById('motivationalText');
            const progressArcElement = document.getElementById('progressArc');
            const statusIndicatorElement = document.getElementById('statusIndicator');
            const analogTimerSvg = document.getElementById('analogTimerSvg');
            const studentSubjectsDisplay = document.getElementById('studentSubjectsDisplay');
            const timerCircleElement = document.querySelector('.timer-circle');

            const currentPeriod = getCurrentPeriod(now);
            const upcomingLesson = getUpcomingLesson(now);

            // Functie om Nederlandse dag en datum te krijgen
            function getDutchDateString(date) {
                const days = ['Zondag', 'Maandag', 'Dinsdag', 'Woensdag', 'Donderdag', 'Vrijdag', 'Zaterdag'];
                const months = ['januari', 'februari', 'maart', 'april', 'mei', 'juni',
                              'juli', 'augustus', 'september', 'oktober', 'november', 'december'];
                
                const dayName = days[date.getDay()].toLowerCase();
                const day = date.getDate();
                const monthName = months[date.getMonth()];
                
                return `${dayName} ${day} ${monthName}`;
            }

            // Wis de inhoud van studentSubjectsDisplay bij elke update
            studentSubjectsDisplay.innerHTML = '';

            // Define currentDay variable
            const dutchDays = ['zondag', 'maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag'];
            const currentDay = dutchDays[now.getDay()];

            // Update datum informatie
            const dateString = getDutchDateString(now);
            dateInfoElement.textContent = `Het is vandaag ${dateString}`;

            // Check of we in de laatste minuut van een pauze/lunch zitten voordat een les begint
            if (currentPeriod && isLastMinuteBeforeLesson(currentPeriod, now)) {
                // Verander alleen het motivational text bericht
                motivationalTextElement.textContent = "Over 1 minuut start de les!";
            }
            
            if (currentPeriod) {
                const { remaining, progress } = calculateTimeRemaining(currentPeriod, now);

                // Show timer circle during lessons and breaks
                timerCircleElement.style.display = 'block';

                // Update period name
                periodNameElement.textContent = currentPeriod.name;
                periodNameElement.className = `period-name ${currentPeriod.type}`;

                // Update time remaining
                timeRemainingElement.textContent = remaining;

                // Update motivational text
                motivationalTextElement.textContent = currentPeriod.motivationalText;
                motivationalTextElement.className = `motivational-text ${currentPeriod.type}`;

                // Update progress arc (this will be implemented later)
                // For now, just ensure the element exists
                    const centerX = 140;
                    const centerY = 140;
                    const radius = 130;

                    // Calculate angle from progress percentage
                    const angle = (progress / 100) * 360;

                    // Convert angle to radians
                    const angleRad = (angle * Math.PI) / 180;

                    // Calculate end point of the arc
                    const endX = centerX + radius * Math.sin(angleRad);
                    const endY = centerY - radius * Math.cos(angleRad);

                    // Create the path for the filled arc (pie slice)
                    const largeArcFlag = angle > 180 ? 1 : 0;
                    const pathData = `M ${centerX} ${centerY} L ${centerX} ${centerY - radius} A ${radius} ${radius} 0 ${largeArcFlag} 1 ${endX} ${endY} Z`;

                    progressArcElement.setAttribute('d', pathData);
                if (progressArcElement) {
                    // Progress arc logic will be added here
                }

                // Update status indicator
                statusIndicatorElement.className = `status-indicator ${currentPeriod.type}`;

                // Toon leerlingvakken alleen tijdens lesuren
                if (currentPeriod.type === 'lesson') {
                    // Maak het element zichtbaar
                    studentSubjectsDisplay.style.display = 'grid';

                    students.forEach(student => {
                        const daySchedule = student.schedule[currentDay];
                        const subject = daySchedule ? daySchedule[currentPeriod.name] : null;
                        if (subject) {
                            const p = document.createElement('p');
                            p.innerHTML = `<strong>${student.name}:</strong> ${subject}`;
                            studentSubjectsDisplay.appendChild(p);
                        }
                    });
                } else {
                    // Verberg het element als het geen lesuur is
                    studentSubjectsDisplay.style.display = 'none';
                }
            } else {
                // No current period - check if we're in the morning welcome period (08:00 - first lesson)
                const currentSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
                const welcomeStartSeconds = 8 * 3600; // 08:00:00
                const firstLessonStartSeconds = timeToSeconds(schedule[0].startTime);

                if (currentSeconds >= welcomeStartSeconds && currentSeconds < firstLessonStartSeconds) {
                    // Morning welcome period
                    periodNameElement.textContent = 'Goedemorgen, welkom in T4!';
                    periodNameElement.className = 'period-name';

                    // Hide timer circle completely
                    timerCircleElement.style.display = 'none';

                    // Calculate time until first lesson
                    const secondsUntilLesson = firstLessonStartSeconds - currentSeconds;
                    const minutesUntilLesson = Math.ceil(secondsUntilLesson / 60);
                    motivationalTextElement.textContent = `De les begint over ${minutesUntilLesson} minuten!`;
                    motivationalTextElement.className = 'motivational-text';

                    statusIndicatorElement.className = 'status-indicator';
                    studentSubjectsDisplay.style.display = 'none';

                    // Clear progress arc
                    progressArcElement.setAttribute('d', '');
                } else {
                    // Outside of school hours
                    periodNameElement.textContent = 'Geen les op dit moment';
                    periodNameElement.className = 'period-name';

                    // Hide timer circle
                    timerCircleElement.style.display = 'none';

                    motivationalTextElement.textContent = 'De school is gesloten of er is geen les ingepland.';
                    motivationalTextElement.className = 'motivational-text';
                    statusIndicatorElement.className = 'status-indicator inactive';
                    studentSubjectsDisplay.style.display = 'none';

                    // Clear progress arc
                    progressArcElement.setAttribute('d', '');
                }
            }
        }

        // Update display every second
        setInterval(updateDisplay, 1000);
        
        // Initial display update
        updateDisplay();
    </script>
</body>
</html>'
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
