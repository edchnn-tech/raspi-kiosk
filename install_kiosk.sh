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
    cat > "$INDEX_FILE" <<'HTML'
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Digitale Lestimer voor Klaslokalen</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Arial', sans-serif; background: #f3f4f6; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .timer-container { background: white; border-radius: 30px; padding: 60px 40px; box-shadow: 0 20px 60px rgba(0, 0, 0, 0.1); text-align: center; max-width: 650px; width: 100%; position: relative; }
        .period-info { margin-bottom: 60px; }
        .date-info { font-size: 18px; color: #333; margin-bottom: 55px; font-weight: normal; }
        .period-name { font-size: 48px; font-weight: bold; color: #333; }
        .period-name.lesson { color: #dc2626; }
        .period-name.break { color: #059669; }
        .period-name.lunch { color: #ea580c; }
        .timer-circle { position: relative; width: 525px; height: 525px; margin: 0 auto 40px; background: linear-gradient(145deg, #f0f0f0, #cacaca); border-radius: 50%; box-shadow: inset -10px -10px 20px rgba(255, 255, 255, 0.5), inset 10px 10px 20px rgba(0, 0, 0, 0.1), 0 10px 20px rgba(0, 0, 0, 0.1); }
        .timer-inner { position: absolute; top: 37px; left: 37px; width: 450px; height: 450px; border-radius: 50%; background: white; display: flex; flex-direction: column; align-items: center; justify-content: center; box-shadow: inset 5px 5px 10px rgba(0, 0, 0, 0.1), inset -5px -5px 10px rgba(255, 255, 255, 0.8); }
        .time-remaining { font-size: 50px; font-weight: 800; color: #333; margin-bottom: 10px; }
        .time-label { font-size: 14px; color: #666; text-transform: uppercase; letter-spacing: 1px; }
        .analog-timer-svg { position: absolute; top: 0; left: 0; width: 100%; height: 100%; transform: rotate(-90deg); }
        .motivational-text { font-size: 18px; color: #333; margin-top: 60px; margin-bottom: 60px; padding: 15px; background: #f8f9fa; border-radius: 15px; }
        .motivational-text.break { background: #f0fdf4; }
        .motivational-text.lunch { background: #fff7ed; }
        .status-indicator { position: absolute; top: 15px; right: 15px; width: 12px; height: 12px; border-radius: 50%; background: #6b7280; animation: pulse 2s infinite; }
        .status-indicator.inactive { background: #gray; animation: none; }
        @keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.5; } 100% { opacity: 1; } }
        .student-subjects-list { margin-top: 30px; padding: 20px; background: #f8f9fa; border-radius: 15px; box-shadow: inset 0 2px 4px rgba(0,0,0,0.06); text-align: center; display: grid; grid-template-columns: 1fr 1fr; gap: 10px; font-size: 18px; }
        .student-subjects-list p { color: #555; line-height: 1.3; margin-bottom: 5px; }
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
                    <circle cx="140" cy="140" r="130" fill="white" stroke="#e5e7eb" stroke-width="5"/>
                    <path id="progressArc" fill="#dc2626" stroke="none"/>
                    <circle cx="140" cy="140" r="8" fill="#6b7280"/>
                </svg>
                <div class="timer-inner">
                    <div class="time-remaining" id="timeRemaining">--:--</div>
                </div>
            </div>
            <div class="motivational-text" id="motivationalText">Welkom!</div>
            <div class="student-subjects-list" id="studentSubjectsDisplay"></div>
        </div>
    </div>
    <script>
        const schedule=[{name:"Het 1e uur",startTime:"08:30:45",endTime:"09:15:45",type:"lesson",motivationalText:"Succes, zet hem op vandaag! 💪"},{name:"Pauze",startTime:"09:15:45",endTime:"09:25:45",type:"break",motivationalText:"10 minuten pauze! Even bijkomen. ☕"},{name:"Het 2e uur",startTime:"09:25:45",endTime:"10:00:45",type:"lesson",motivationalText:"Succes dit 2e uur alweer! 🚀"},{name:"Pauze",startTime:"10:00:45",endTime:"10:10:45",type:"break",motivationalText:"10 minuten pauze! Stretch jezelf even. 🤸"},{name:"Het 3e uur",startTime:"10:10:45",endTime:"10:45:45",type:"lesson",motivationalText:"Het 3e uur alweer, bijna tijd om te eten! 🎯"},{name:"Eetpauze",startTime:"10:45:45",endTime:"11:05:45",type:"lunch",motivationalText:"Eetsmakelijk! Geniet van je pauze! 🍽️"},{name:"Pauze",startTime:"11:05:45",endTime:"11:25:45",type:"break",motivationalText:"Nog even pauze! Bijna weer aan de slag. 😊"},{name:"Het 4e uur",startTime:"11:30:45",endTime:"12:05:45",type:"lesson",motivationalText:"Fantastisch! De helft van de dag is al voorbij! 🌟"},{name:"Pauze",startTime:"12:05:45",endTime:"12:15:45",type:"break",motivationalText:"10 minuten pauze! 👏"},{name:"Het 5e uur",startTime:"12:15:45",endTime:"12:50:45",type:"lesson",motivationalText:"Het 5e uur is weer begonnen! 🏁"},{name:"Pauze",startTime:"12:50:45",endTime:"13:00:45",type:"break",motivationalText:"10 minuten pauze! De eindstreep komt in zicht! 👀"},{name:"Het 6e uur",startTime:"13:00:45",endTime:"13:35:45",type:"lesson",motivationalText:"Het 6e uur, zet hem op! ✨"},{name:"Pauze",startTime:"13:35:45",endTime:"13:45:45",type:"break",motivationalText:"10 minuten pauze! 🏃"},{name:"Het 7e uur",startTime:"13:45:45",endTime:"14:20:45",type:"lesson",motivationalText:"Één na laatste uurtje alweer! 🎉"},{name:"Pauze",startTime:"14:20:45",endTime:"14:45:45",type:"break",motivationalText:"Nog een pauze! Bijna klaar voor vandaag! 💪"},{name:"Het 8e uur",startTime:"14:45:45",endTime:"15:30:45",type:"lesson",motivationalText:"Het allerlaatste uur! 🏆"}];
        const students=[{name:"Tygo",schedule:{"maandag":{"Het 1e uur":"WI","Het 2e uur":"GD","Het 3e uur":"NE","Het 4e uur":"BWI","Het 5e uur":"BWI","Het 6e uur":"BWI","Het 7e uur":"EN","Het 8e uur":"--"},"dinsdag":{"Het 1e uur":"WI","Het 2e uur":"NASK","Het 3e uur":"NE","Het 4e uur":"EN","Het 5e uur":"BWI","Het 6e uur":"BWI","Het 7e uur":"BWI","Het 8e uur":"BWI"},"woensdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"NASK","Het 5e uur":"EN","Het 6e uur":"LO","Het 7e uur":"WI","Het 8e uur":"--"},"donderdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"GD","Het 5e uur":"Qompas","Het 6e uur":"WI","Het 7e uur":"NE","Het 8e uur":"--"},"vrijdag":{"Het 1e uur":"Stage","Het 2e uur":"Stage","Het 3e uur":"Stage","Het 4e uur":"Stage","Het 5e uur":"Stage","Het 6e uur":"Stage","Het 7e uur":"Stage","Het 8e uur":"Stage"}}},{name:"Thomas",schedule:{"maandag":{"Het 1e uur":"WI","Het 2e uur":"NE","Het 3e uur":"EN","Het 4e uur":"EC","Het 5e uur":"LO"},"dinsdag":{"Het 1e uur":"EN","Het 2e uur":"NASK","Het 3e uur":"WI","Het 4e uur":"GD","Het 5e uur":"Qompas"},"woensdag":{"Het 1e uur":"GS","Het 2e uur":"BIO","Het 3e uur":"GD","Het 4e uur":"EN","Het 5e uur":"WI","Het 6e uur":"LO"},"donderdag":{"Het 1e uur":"BIO","Het 2e uur":"GS","Het 3e uur":"WI","Het 4e uur":"Duits","Het 5e uur":"NE"},"vrijdag":{"Het 1e uur":"EC","Het 2e uur":"Duits","Het 3e uur":"NE","Het 4e uur":"NASK"}}},{name:"Levi",schedule:{"maandag":{"Het 1e uur":"WI","Het 2e uur":"BIO","Het 3e uur":"GD","Het 4e uur":"EC","Het 5e uur":"LO"},"dinsdag":{"Het 3e uur":"WI","Het 4e uur":"EN","Het 5e uur":"EC","Het 6e uur":"Z&W","Het 7e uur":"Z&W"},"woensdag":{"Het 1e uur":"GD","Het 2e uur":"Z&W","Het 3e uur":"Z&W","Het 4e uur":"BIO","Het 5e uur":"NE","Het 6e uur":"LO"},"donderdag":{"Het 1e uur":"WI","Het 2e uur":"EN","Het 3e uur":"EC","Het 4e uur":"BIO","Het 5e uur":"NE","Het 6e uur":"Qompas"},"vrijdag":{"Het 1e uur":"BIO","Het 2e uur":"Z&W","Het 3e uur":"WI","Het 4e uur":"EN","Het 5e uur":"NE","Het 6e uur":"EC"}}},{name:"Jonah",schedule:{"maandag":{"Het 1e uur":"Z&W","Het 2e uur":"Z&W","Het 3e uur":"Z&W","Het 4e uur":"NE","Het 5e uur":"LO","Het 6e uur":"BIO","Het 7e uur":"EN"},"dinsdag":{"Het 1e uur":"BIO","Het 2e uur":"Z&W","Het 3e uur":"Z&W","Het 4e uur":"Z&W","Het 5e uur":"EN","Het 6e uur":"WI","Het 7e uur":"MA"},"woensdag":{"Het 1e uur":"GD","Het 2e uur":"NE","Het 3e uur":"EN","Het 4e uur":"Z&W","Het 5e uur":"Z&W","Het 6e uur":"LO","Het 7e uur":"WI"},"donderdag":{"Het 1e uur":"BIO","Het 2e uur":"NE","Het 3e uur":"EN","Het 4e uur":"Z&W","Het 5e uur":"Z&W","Het 6e uur":"Z&W"},"vrijdag":{"Het 1e uur":"Z&W","Het 2e uur":"Z&W","Het 3e uur":"Z&W","Het 4e uur":"MA","Het 5e uur":"NE","Het 6e uur":"WI","Het 7e uur":"GD"}}},{name:"Nathan S",schedule:{"maandag":{"Het 1e uur":"NE","Het 2e uur":"EN","Het 3e uur":"AK","Het 4e uur":"REK","Het 5e uur":"LO"},"dinsdag":{"Het 1e uur":"NE","Het 2e uur":"Qompas","Het 3e uur":"EC","Het 4e uur":"MA","Het 5e uur":"EN"},"woensdag":{"Het 1e uur":"GS","Het 2e uur":"NE","Het 3e uur":"MA","Het 4e uur":"GD","Het 5e uur":"EC","Het 6e uur":"LO"},"donderdag":{"Het 1e uur":"AK","Het 2e uur":"EN","Het 3e uur":"GS","Het 4e uur":"BIO"},"vrijdag":{"Het 2e uur":"NE","Het 3e uur":"GD","Het 4e uur":"BIO","Het 5e uur":"EN"}}},{name:"Chibueze",schedule:{"maandag":{"Het 1e uur":"E&O","Het 2e uur":"E&O","Het 3e uur":"E&O","Het 4e uur":"NE","Het 5e uur":"LO","Het 6e uur":"EC","Het 7e uur":"E&O","Het 8e uur":"E&O"},"dinsdag":{"Het 1e uur":"MA","Het 2e uur":"E&O","Het 3e uur":"E&O","Het 4e uur":"E&O","Het 5e uur":"WI","Het 6e uur":"Qompas"},"woensdag":{"Het 1e uur":"EC","Het 2e uur":"GD","Het 3e uur":"EN","Het 4e uur":"E&O","Het 5e uur":"E&O","Het 6e uur":"LO","Het 7e uur":"NE"},"donderdag":{"Het 1e uur":"MA","Het 2e uur":"WI","Het 3e uur":"EN","Het 4e uur":"E&O","Het 5e uur":"E&O","Het 6e uur":"E&O","Het 7e uur":"NE","Het 8e uur":"GD"},"vrijdag":{"Het 1e uur":"E&O","Het 2e uur":"E&O","Het 3e uur":"E&O","Het 4e uur":"EC","Het 5e uur":"WI","Het 6e uur":"EN"}}},{name:"Hendrik",schedule:{"maandag":{"Het 1e uur":"NE","Het 2e uur":"EN","Het 3e uur":"NA","Het 4e uur":"WI","Het 5e uur":"LO","Het 6e uur":"EC"},"dinsdag":{"Het 1e uur":"NE","Het 2e uur":"Qompas","Het 3e uur":"NA","Het 4e uur":"WI","Het 5e uur":"EN"},"woensdag":{"Het 2e uur":"HW","Het 3e uur":"MA","Het 4e uur":"GD","Het 5e uur":"NE","Het 6e uur":"BWI","Het 7e uur":"BWI","Het 8e uur":"BWI"},"donderdag":{"Het 1e uur":"AK","Het 2e uur":"EN","Het 3e uur":"NA","Het 4e uur":"MA","Het 5e uur":"EC","Het 6e uur":"HW"},"vrijdag":{"Het 1e uur":"AK","Het 2e uur":"NE","Het 3e uur":"GD","Het 4e uur":"WI","Het 5e uur":"EN"}}},{name:"Mart",schedule:{"maandag":{"Het 2e uur":"NE","Het 3e uur":"EC","Het 4e uur":"E&O","Het 5e uur":"E&O","Het 6e uur":"E&O","Het 7e uur":"EC","Het 8e uur":"DU"},"dinsdag":{"Het 2e uur":"NE","Het 3e uur":"DU","Het 4e uur":"Qompas","Het 5e uur":"E&O","Het 6e uur":"E&O","Het 7e uur":"EN"},"woensdag":{"Het 1e uur":"E&O","Het 2e uur":"E&O","Het 3e uur":"E&O","Het 4e uur":"GD","Het 5e uur":"EN","Het 6e uur":"LO","Het 7e uur":"DU"},"donderdag":{"Het 1e uur":"DU","Het 2e uur":"E&O","Het 3e uur":"E&O","Het 4e uur":"NE","Het 5e uur":"GD","Het 6e uur":"EN","Het 7e uur":"EC"},"vrijdag":{"Het 1e uur":"Stage","Het 2e uur":"Stage","Het 3e uur":"Stage","Het 4e uur":"Stage","Het 5e uur":"Stage","Het 6e uur":"Stage","Het 7e uur":"Stage","Het 8e uur":"Stage"}}},{name:"Jurrian",schedule:{"maandag":{"Het 1e uur":"WI","Het 2e uur":"GD","Het 3e uur":"NE","Het 4e uur":"BWI","Het 5e uur":"BWI","Het 6e uur":"BWI","Het 7e uur":"EN"},"dinsdag":{"Het 1e uur":"WI","Het 2e uur":"NASK","Het 3e uur":"NE","Het 4e uur":"EN","Het 5e uur":"BWI","Het 6e uur":"BWI","Het 7e uur":"BWI","Het 8e uur":"BWI"},"woensdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"NASK","Het 5e uur":"EN","Het 6e uur":"LO","Het 7e uur":"WI"},"donderdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"GD","Het 5e uur":"Qompas","Het 6e uur":"WI","Het 7e uur":"NE"},"vrijdag":{"Het 1e uur":"Stage","Het 2e uur":"Stage ","Het 3e uur":"Stage ","Het 4e uur":"Stage","Het 5e uur":"Stage","Het 6e uur":"Stage","Het 7e uur":"Stage","Het 8e uur":"Stage"}}},{name:"Thieme",schedule:{"maandag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"GD","Het 5e uur":"LO","Het 6e uur":"MA","Het 7e uur":"BWI","Het 8e uur":"BWI"},"dinsdag":{"Het 1e uur":"EN","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"BWI","Het 5e uur":"Qompas","Het 6e uur":"WI","Het 7e uur":"NASK"},"woensdag":{"Het 1e uur":"NE","Het 2e uur":"WI","Het 3e uur":"EN","Het 4e uur":"BWI","Het 5e uur":"BWI","Het 6e uur":"LO","Het 7e uur":"NASK"},"donderdag":{"Het 1e uur":"NE","Het 2e uur":"MA","Het 3e uur":"EN","Het 4e uur":"BWI","Het 5e uur":"BWI","Het 6e uur":"BWI","Het 7e uur":"GD"},"vrijdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"WI","Het 5e uur":"NE","Het 6e uur":"NASK"}}},{name:"Joah",schedule:{"maandag":{"Het 3e uur":"EN","Het 4e uur":"EC","Het 5e uur":"WI","Het 6e uur":"NE"},"dinsdag":{"Het 3e uur":"WI","Het 4e uur":"GS","Het 5e uur":"NA","Het 6e uur":"EN"},"woensdag":{"Het 3e uur":"GD","Het 4e uur":"BI","Het 5e uur":"NE","Het 6e uur":"GS"},"vrijdag":{"Het 3e uur":"BI","Het 4e uur":"NA","Het 5e uur":"DU","Het 6e uur":"EC"}}},{name:"Nathan V",schedule:{"maandag":{"Het 1e uur":"NA","Het 2e uur":"WI","Het 3e uur":"NE","Het 4e uur":"BWI","Het 5e uur":"BWI","Het 6e uur":"BWI"},"dinsdag":{"Het 1e uur":"Qompas","Het 2e uur":"GD","Het 3e uur":"EN","Het 4e uur":"WI","Het 5e uur":"BWI","Het 6e uur":"BWI","Het 7e uur":"BWI","Het 8e uur":"BWI"},"woensdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"NA","Het 5e uur":"NE","Het 6e uur":"LO"},"donderdag":{"Het 1e uur":"BWI","Het 2e uur":"BWI","Het 3e uur":"BWI","Het 4e uur":"NA","Het 5e uur":"EN","Het 6e uur":"WI"},"vrijdag":{"Het 1e uur":"EN","Het 2e uur":"NE","Het 3e uur":"WI","Het 4e uur":"GD"}}}];
        function timeToSeconds(e){const t=e.split(":").map(Number);return 3600*t[0]+60*t[1]+(t[2]||0)}function getCurrentPeriod(e){const t=3600*e.getHours()+60*e.getMinutes()+e.getSeconds();for(const o of schedule){const n=timeToSeconds(o.startTime),i=timeToSeconds(o.endTime);if(t>=n&&t<i)return o}return null}function calculateTimeRemaining(e,t){const o=3600*t.getHours()+60*t.getMinutes()+t.getSeconds(),n=timeToSeconds(e.startTime),i=timeToSeconds(e.endTime),r=i-o;let s;return s=Math.floor(r/60)>0?`${Math.floor(r/60)} min`:`${Math.floor(r%60)}s`,{remaining:s,progress:Math.min(100,Math.max(0,(o-n)/(i-n)*100))}}
        function updateDisplay(){const e=getCurrentPeriod(new Date);const t=document.getElementById("periodName"),o=document.getElementById("dateInfo"),n=document.getElementById("timeRemaining"),i=document.getElementById("motivationalText"),r=document.getElementById("progressArc"),s=document.getElementById("statusIndicator"),a=document.getElementById("studentSubjectsDisplay"),d=document.querySelector(".timer-circle");const l=['zondag','maandag','dinsdag','woensdag','donderdag','vrijdag','zaterdag'],c=l[new Date().getDay()];o.textContent=`Het is vandaag ${((e=new Date)=>{const t=['zondag','maandag','dinsdag','woensdag','donderdag','vrijdag','zaterdag'],o=['januari','februari','maart','april','mei','juni','juli','augustus','september','oktober','november','december'];return`${t[e.getDay()]} ${e.getDate()} ${o[e.getMonth()]}`})(new Date)}`;if(e){const{remaining:o,progress:l}=calculateTimeRemaining(e,new Date);d.style.display="block",t.textContent=e.name,t.className=`period-name ${e.type}`,n.textContent=o,i.textContent=e.motivationalText,i.className=`motivational-text ${e.type}`;const c=140,u=140,m=130,p=(l/100)*360,h=p*Math.PI/180,g=c+m*Math.sin(h),f=u-m*Math.cos(h);r.setAttribute("d",`M ${c} ${u} L ${c} ${u-m} A ${m} ${m} 0 ${p>180?1:0} 1 ${g} ${f} Z`),s.className=`status-indicator ${e.type}`,"lesson"===e.type?(a.style.display="grid",a.innerHTML="",students.forEach(t=>{const o=t.schedule[c]?t.schedule[c][e.name]:null;if(o){const e=document.createElement("p");e.innerHTML=`<strong>${t.name}:</strong> ${o}`,a.appendChild(e)}})):a.style.display="none"}else{d.style.display="none",t.textContent="Geen les op dit moment",t.className="period-name",i.textContent="De school is gesloten of er is geen les ingepland.",i.className="motivational-text",s.className="status-indicator inactive",a.style.display="none",r.setAttribute("d","")}}setInterval(updateDisplay,1e3),updateDisplay();
    </script>
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
  configure_hdmi_never_sleep
  disable_console_blank
  prepare_kiosk_files
  create_xinitrc
  create_systemd_service
  start_now
  summary
}

main "$@"
EOF
