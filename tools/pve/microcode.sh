#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster), MickLesk
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
    ____                                               __  ____                                __
   / __ \_________  ________  ______________  _____   /  |/  (_)_____________  _________  ____/ /__
  / /_/ / ___/ __ \/ ___/ _ \/ ___/ ___/ __ \/ ___/  / /|_/ / / ___/ ___/ __ \/ ___/ __ \/ __  / _ \
 / ____/ /  / /_/ / /__/  __(__  |__  ) /_/ / /     / /  / / / /__/ /  / /_/ / /__/ /_/ / /_/ /  __/
/_/   /_/   \____/\___/\___/____/____/\____/_/     /_/  /_/_/\___/_/   \____/\___/\____/\__,_/\___/

EOF
}

RD=$(echo "\033[01;31m")
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }

header_info

# Enhanced CPU detection
get_cpu_info() {
  CPU_VENDOR=$(lscpu | grep -oP 'Vendor ID:\s*\K\S+' | head -n 1)
  CPU_MODEL=$(lscpu | grep -oP 'Model name:\s*\K.*' | head -n 1 | xargs)
  CPU_FAMILY=$(lscpu | grep -oP 'CPU family:\s*\K\d+' | head -n 1)
  CPU_MODEL_NUM=$(lscpu | grep -oP 'Model:\s*\K\d+' | head -n 1)
  CPU_STEPPING=$(lscpu | grep -oP 'Stepping:\s*\K\d+' | head -n 1)

  # Detect CPU generation/architecture
  CPU_ARCH="Unknown"
  if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    case "$CPU_MODEL_NUM" in
    # Intel Core Ultra (Meteor Lake)
    170 | 171 | 172) CPU_ARCH="Meteor Lake (Core Ultra)" ;;
    # Raptor Lake / Raptor Lake Refresh
    183 | 186 | 191) CPU_ARCH="Raptor Lake (13th/14th Gen)" ;;
    # Alder Lake
    151 | 154 | 167) CPU_ARCH="Alder Lake (12th Gen)" ;;
    # Rocket Lake
    167) CPU_ARCH="Rocket Lake (11th Gen)" ;;
    # Comet Lake
    165 | 166) CPU_ARCH="Comet Lake (10th Gen)" ;;
    # Ice Lake
    125 | 126) CPU_ARCH="Ice Lake (10th Gen)" ;;
    # Coffee Lake
    142 | 158) CPU_ARCH="Coffee Lake (8th/9th Gen)" ;;
    # Skylake / Kaby Lake
    78 | 94) CPU_ARCH="Skylake/Kaby Lake (6th/7th Gen)" ;;
    # Xeon Scalable
    85 | 106 | 108 | 143) CPU_ARCH="Xeon Scalable" ;;
    # Atom
    92 | 95 | 122 | 156) CPU_ARCH="Atom" ;;
    *) CPU_ARCH="Intel (Model $CPU_MODEL_NUM)" ;;
    esac
  elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
    case "$CPU_FAMILY" in
    # Zen 5 (Granite Ridge, Turin)
    26) CPU_ARCH="Zen 5 (Ryzen 9000 / EPYC Turin)" ;;
    # Zen 4 (Raphael, Genoa)
    25)
      if [ "$CPU_MODEL_NUM" -ge 96 ]; then
        CPU_ARCH="Zen 4 (Ryzen 7000 / EPYC Genoa)"
      else
        CPU_ARCH="Zen 3 (Ryzen 5000 / EPYC Milan)"
      fi
      ;;
    # Zen 3
    25) CPU_ARCH="Zen 3 (Ryzen 5000)" ;;
    # Zen 2
    23)
      if [ "$CPU_MODEL_NUM" -ge 49 ]; then
        CPU_ARCH="Zen 2 (Ryzen 3000 / EPYC Rome)"
      else
        CPU_ARCH="Zen/Zen+ (Ryzen 1000/2000)"
      fi
      ;;
    # Older AMD
    21) CPU_ARCH="Bulldozer/Piledriver" ;;
    *) CPU_ARCH="AMD (Family $CPU_FAMILY)" ;;
    esac
  fi
}

# Get current microcode revision
get_current_microcode() {
  # Try multiple sources for microcode version
  current_microcode=$(journalctl -k 2>/dev/null | grep -i 'microcode' | grep -oP '(revision|updated.*to|Current revision:)\s*\K0x[0-9a-fA-F]+' | tail -1)

  if [ -z "$current_microcode" ]; then
    current_microcode=$(dmesg 2>/dev/null | grep -i 'microcode' | grep -oP '0x[0-9a-fA-F]+' | tail -1)
  fi

  if [ -z "$current_microcode" ]; then
    # Try reading from CPU directly
    if [ -f /sys/devices/system/cpu/cpu0/microcode/version ]; then
      current_microcode=$(cat /sys/devices/system/cpu/cpu0/microcode/version 2>/dev/null)
    fi
  fi

  [ -z "$current_microcode" ] && current_microcode="Not detected"
}

# Display CPU information
show_cpu_info() {
  echo -e "\n${BL}╔══════════════════════════════════════════════════════════════╗${CL}"
  echo -e "${BL}║${CL}                    ${GN}CPU Information${CL}                           ${BL}║${CL}"
  echo -e "${BL}╠══════════════════════════════════════════════════════════════╣${CL}"
  echo -e "${BL}║${CL} ${YW}Model:${CL}      $CPU_MODEL"
  echo -e "${BL}║${CL} ${YW}Vendor:${CL}     $CPU_VENDOR"
  echo -e "${BL}║${CL} ${YW}Architecture:${CL} $CPU_ARCH"
  echo -e "${BL}║${CL} ${YW}Family/Model:${CL} $CPU_FAMILY / $CPU_MODEL_NUM (Stepping $CPU_STEPPING)"
  echo -e "${BL}║${CL} ${YW}Microcode:${CL}  $current_microcode"
  echo -e "${BL}╚══════════════════════════════════════════════════════════════╝${CL}\n"
}

intel() {
  if ! dpkg -s iucode-tool >/dev/null 2>&1; then
    msg_info "Installing iucode-tool (Intel microcode updater)"
    apt-get install -y iucode-tool &>/dev/null
    msg_ok "Installed iucode-tool"
  else
    msg_ok "Intel iucode-tool is already installed"
    sleep 1
  fi

  msg_info "Fetching available Intel microcode packages"
  intel_microcode=$(curl -fsSL "https://ftp.debian.org/debian/pool/non-free-firmware/i/intel-microcode/" | grep -oP 'href="intel-microcode[^"]*amd64\.deb"' | sed 's/href="//;s/"//' | sort -V)

  [ -z "$intel_microcode" ] && {
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "No Microcode Found" --msgbox "No microcode packages found. Try again later." 10 68
    msg_error "No microcode packages found"
    exit 1
  }
  msg_ok "Found $(echo "$intel_microcode" | wc -l) packages"

  # Get latest version for recommendation
  latest_version=$(echo "$intel_microcode" | tail -1)

  MICROCODE_MENU=()
  MSG_MAX_LENGTH=0

  while read -r ITEM; do
    [ -z "$ITEM" ] && continue
    OFFSET=2
    ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
    # Mark latest as default ON
    if [ "$ITEM" == "$latest_version" ]; then
      MICROCODE_MENU+=("$ITEM" "(Latest - Recommended)" "ON")
    else
      MICROCODE_MENU+=("$ITEM" "" "OFF")
    fi
  done < <(echo "$intel_microcode")

  microcode=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Intel Microcode - Current: ${current_microcode}" --radiolist "\nCPU: ${CPU_MODEL}\nArchitecture: ${CPU_ARCH}\n\nSelect a microcode package to install:\n" 20 $((MSG_MAX_LENGTH + 65)) 8 "${MICROCODE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

  [ -z "$microcode" ] && {
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "No Microcode Selected" --msgbox "No microcode package selected." 10 68
    msg_info "Exiting"
    sleep 1
    msg_ok "Done"
    exit 0
  }

  msg_info "Downloading Intel Microcode Package: $microcode"
  wget -q "https://ftp.debian.org/debian/pool/non-free-firmware/i/intel-microcode/$microcode" -O "/tmp/$microcode"
  msg_ok "Downloaded $microcode"

  msg_info "Installing $microcode"
  dpkg -i "/tmp/$microcode" &>/dev/null
  msg_ok "Installed $microcode"

  msg_info "Cleaning up"
  rm -f "/tmp/$microcode"
  msg_ok "Cleaned"

  # Try to reload microcode without reboot (if supported)
  if [ -f /sys/devices/system/cpu/microcode/reload ]; then
    msg_info "Attempting live microcode reload"
    echo 1 >/sys/devices/system/cpu/microcode/reload 2>/dev/null && msg_ok "Live reload successful" || msg_info "Live reload not supported, reboot required"
  fi

  # Check new version
  sleep 1
  new_microcode=$(cat /sys/devices/system/cpu/cpu0/microcode/version 2>/dev/null || echo "Check after reboot")

  echo -e "\n${GN}╔══════════════════════════════════════════════════════════════╗${CL}"
  echo -e "${GN}║${CL}                    ${GN}Installation Complete${CL}                     ${GN}║${CL}"
  echo -e "${GN}╠══════════════════════════════════════════════════════════════╣${CL}"
  echo -e "${GN}║${CL} ${YW}Previous Microcode:${CL} $current_microcode"
  echo -e "${GN}║${CL} ${YW}New Microcode:${CL}      $new_microcode"
  echo -e "${GN}╚══════════════════════════════════════════════════════════════╝${CL}"
  echo -e "\n${YW}Note:${CL} A system reboot is recommended to fully apply the microcode update.\n"
}

amd() {
  msg_info "Fetching available AMD microcode packages"
  amd_microcode=$(curl -fsSL "https://ftp.debian.org/debian/pool/non-free-firmware/a/amd64-microcode/" | grep -oP 'href="amd64-microcode[^"]*amd64\.deb"' | sed 's/href="//;s/"//' | sort -V)

  [ -z "$amd_microcode" ] && {
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "No Microcode Found" --msgbox "No microcode packages found. Try again later." 10 68
    msg_error "No microcode packages found"
    exit 1
  }
  msg_ok "Found $(echo "$amd_microcode" | wc -l) packages"

  # Get latest version for recommendation
  latest_version=$(echo "$amd_microcode" | tail -1)

  MICROCODE_MENU=()
  MSG_MAX_LENGTH=0

  while read -r ITEM; do
    [ -z "$ITEM" ] && continue
    OFFSET=2
    ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
    # Mark latest as default ON
    if [ "$ITEM" == "$latest_version" ]; then
      MICROCODE_MENU+=("$ITEM" "(Latest - Recommended)" "ON")
    else
      MICROCODE_MENU+=("$ITEM" "" "OFF")
    fi
  done < <(echo "$amd_microcode")

  microcode=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "AMD Microcode - Current: ${current_microcode}" --radiolist "\nCPU: ${CPU_MODEL}\nArchitecture: ${CPU_ARCH}\n\nSelect a microcode package to install:\n" 20 $((MSG_MAX_LENGTH + 65)) 8 "${MICROCODE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

  [ -z "$microcode" ] && {
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "No Microcode Selected" --msgbox "No microcode package selected." 10 68
    msg_info "Exiting"
    sleep 1
    msg_ok "Done"
    exit 0
  }

  msg_info "Downloading AMD Microcode Package: $microcode"
  wget -q "https://ftp.debian.org/debian/pool/non-free-firmware/a/amd64-microcode/$microcode" -O "/tmp/$microcode"
  msg_ok "Downloaded $microcode"

  msg_info "Installing $microcode"
  dpkg -i "/tmp/$microcode" &>/dev/null
  msg_ok "Installed $microcode"

  msg_info "Cleaning up"
  rm -f "/tmp/$microcode"
  msg_ok "Cleaned"

  # Try to reload microcode without reboot (if supported)
  if [ -f /sys/devices/system/cpu/microcode/reload ]; then
    msg_info "Attempting live microcode reload"
    echo 1 >/sys/devices/system/cpu/microcode/reload 2>/dev/null && msg_ok "Live reload successful" || msg_info "Live reload not supported, reboot required"
  fi

  # Check new version
  sleep 1
  new_microcode=$(cat /sys/devices/system/cpu/cpu0/microcode/version 2>/dev/null || echo "Check after reboot")

  echo -e "\n${GN}╔══════════════════════════════════════════════════════════════╗${CL}"
  echo -e "${GN}║${CL}                    ${GN}Installation Complete${CL}                     ${GN}║${CL}"
  echo -e "${GN}╠══════════════════════════════════════════════════════════════╣${CL}"
  echo -e "${GN}║${CL} ${YW}Previous Microcode:${CL} $current_microcode"
  echo -e "${GN}║${CL} ${YW}New Microcode:${CL}      $new_microcode"
  echo -e "${GN}╚══════════════════════════════════════════════════════════════╝${CL}"
  echo -e "\n${YW}Note:${CL} A system reboot is recommended to fully apply the microcode update.\n"
}

# Main script
if ! command -v pveversion >/dev/null 2>&1; then
  header_info
  msg_error "No PVE Detected!"
  exit 1
fi

# Gather CPU information
msg_info "Detecting CPU"
get_cpu_info
get_current_microcode
msg_ok "CPU detected: $CPU_VENDOR"

# Show CPU info
show_cpu_info

# Confirmation dialog with CPU info
if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE Processor Microcode" --yesno "CPU: ${CPU_MODEL}\nArchitecture: ${CPU_ARCH}\nCurrent Microcode: ${current_microcode}\n\nThis will check for CPU microcode packages with the option to install.\n\nProceed?" 14 70; then
  msg_info "Cancelled by user"
  exit 0
fi

if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
  intel
elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
  amd
else
  msg_error "CPU vendor '${CPU_VENDOR}' is not supported"
  msg_info "Supported vendors: GenuineIntel, AuthenticAMD"
  exit 1
fi
