#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: gabriel403
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/lovelaze/nebula-sync

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

APP="Nebula-Sync"
APP_TYPE="addon"
INSTALL_PATH="/opt/nebula-sync"
BINARY_PATH="/opt/nebula-sync/nebula-sync"
CONFIG_PATH="/opt/nebula-sync/.env"
SERVICE_PATH="/etc/systemd/system/nebula-sync.service"

function header_info {
  clear
  cat <<"EOF"
 _   __      _       _            _____                      
/ | / /_  __(_)___  (_)___  ___  / ___/___  ______   _____   
/  |/ / / / / / __ \/ / __ \/ _ \ \__ \/ _ \/ ___/ | / / _ \  
/ /|  / /_/ / / / / / / / / /  __/ ___/ /  __/ /   | |/ /  __/  
/_/ |_/\__,_/_/_/ /_/_/ /_/\___/ /____/\___/_/    |___/\___/   
                                                                
EOF
}

YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"
TAB="  "

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }
function msg_warn() { echo -e "⚠️  ${YW}${1}${CL}"; }

function get_ip() {
  local iface ip
  iface=$(ip -4 route | awk '/default/ {print $5; exit}')
  ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
  [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

function detect_os() {
  if [[ -f "/etc/alpine-release" ]]; then
    OS="Alpine"
    msg_error "Alpine Linux is not supported"
    exit 1
  elif [[ -f "/etc/debian_version" ]]; then
    OS="Debian"
  else
    msg_error "Unsupported OS. Exiting."
    exit 1
  fi
}

function stop_service() {
  if systemctl is-active --quiet nebula-sync.service 2>/dev/null; then
    systemctl stop nebula-sync.service
  fi
}

function start_service() {
  systemctl start nebula-sync.service
}

function enable_service() {
  systemctl enable -q --now nebula-sync.service
}

function disable_service() {
  systemctl disable --now nebula-sync.service 2>/dev/null || true
}

function uninstall() {
  msg_info "Uninstalling ${APP}"
  disable_service
  rm -f "$SERVICE_PATH"
  rm -rf "$INSTALL_PATH"
  rm -f "/usr/local/bin/update_nebula-sync"
  systemctl daemon-reload
  msg_ok "${APP} has been uninstalled"
}

function update() {
  msg_info "Checking for updates"
  if check_for_gh_release "nebula-sync" "lovelaze/nebula-sync"; then
    msg_ok "Update available"
    stop_service
    
    msg_info "Backing up configuration"
    if [[ -f "$CONFIG_PATH" ]]; then
      cp "$CONFIG_PATH" /tmp/nebula-sync.env.bak
      msg_ok "Backed up configuration"
    else
      msg_warn "Configuration file not found, skipping backup"
    fi
    
    fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "$INSTALL_PATH" "nebula-sync_.*_linux_.*\.tar\.gz"
    
    msg_info "Restoring configuration"
    if [[ -f /tmp/nebula-sync.env.bak ]]; then
      cp /tmp/nebula-sync.env.bak "$CONFIG_PATH"
      rm -f /tmp/nebula-sync.env.bak
      msg_ok "Restored configuration"
    else
      msg_warn "Backup file not found, keeping existing configuration"
    fi
    
    start_service
    LATEST_RELEASE="v$(cat "$HOME/.nebula-sync" 2>/dev/null || echo '0.0.0')"
    echo "$LATEST_RELEASE" > "/opt/nebula-sync_version.txt"
    msg_ok "Updated ${APP} successfully"
  else
    msg_ok "${APP} is up-to-date"
  fi
}

function gather_config() {
  echo ""
  echo -e "${BL}Nebula-Sync Configuration${CL}"
  echo "─────────────────────────────────────────"
  echo "Enter details for your Pi-hole instances."
  echo "The Primary is your source instance, Replica will sync from it."
  echo ""

  echo -e "${YW}── Primary (Source) Pi-hole Instance ──${CL}"
  read -rp "${TAB}Primary Pi-hole URL/IP (e.g., http://192.168.1.1 or 192.168.1.1): " PRIMARY_URL_INPUT
  PRIMARY_URL_INPUT="${PRIMARY_URL_INPUT:-http://192.168.1.1}"
  [[ ! "$PRIMARY_URL_INPUT" =~ ^https?:// ]] && PRIMARY_URL_INPUT="http://${PRIMARY_URL_INPUT}"
  PRIMARY_URL_INPUT="${PRIMARY_URL_INPUT%/}"
  read -rsp "${TAB}Primary Pi-hole API Password: " PRIMARY_PASSWORD_INPUT
  echo ""
  if [[ -z "$PRIMARY_PASSWORD_INPUT" ]]; then
    msg_error "Primary API password cannot be empty!"
    exit 1
  fi

  echo ""
  echo -e "${YW}── Replica Pi-hole Instance ──${CL}"
  read -rp "${TAB}Replica Pi-hole URL/IP (e.g., http://192.168.1.2 or 192.168.1.2): " REPLICAS_URL_INPUT
  REPLICAS_URL_INPUT="${REPLICAS_URL_INPUT:-http://192.168.1.2}"
  [[ ! "$REPLICAS_URL_INPUT" =~ ^https?:// ]] && REPLICAS_URL_INPUT="http://${REPLICAS_URL_INPUT}"
  REPLICAS_URL_INPUT="${REPLICAS_URL_INPUT%/}"
  read -rsp "${TAB}Replica Pi-hole API Password: " REPLICAS_PASSWORD_INPUT
  echo ""
  if [[ -z "$REPLICAS_PASSWORD_INPUT" ]]; then
    msg_error "Replica API password cannot be empty!"
    exit 1
  fi

  echo ""
  echo -e "${BL}Sync Options${CL}"
  echo "─────────────────────────────────────────"
  echo "What should Nebula-Sync synchronize?"
  echo ""
  echo " 1) Sync all settings (default)"
  echo " 2) Custom selection"
  echo ""
  read -r -p "${TAB}Select sync mode [1]: " SYNC_MODE
  SYNC_MODE="${SYNC_MODE:-1}"

  FULL_SYNC="true"
  if [[ "$SYNC_MODE" == "2" ]]; then
    FULL_SYNC="false"
    echo ""
    echo -e "${BL}Custom Sync Selection${CL}"
    echo "─────────────────────────────────────────"
    echo "Select which items to synchronize (y/n):"
    echo ""
    
    read -rp "${TAB}Sync DNS configuration? [y/N]: " SYNC_CONFIG_DNS_INPUT
    SYNC_CONFIG_DNS="${SYNC_CONFIG_DNS_INPUT:-n}"
    [[ "$SYNC_CONFIG_DNS" =~ ^[yY] ]] && SYNC_CONFIG_DNS="true" || SYNC_CONFIG_DNS="false"
    
    read -rp "${TAB}Sync DHCP configuration? [y/N]: " SYNC_CONFIG_DHCP_INPUT
    SYNC_CONFIG_DHCP="${SYNC_CONFIG_DHCP_INPUT:-n}"
    [[ "$SYNC_CONFIG_DHCP" =~ ^[yY] ]] && SYNC_CONFIG_DHCP="true" || SYNC_CONFIG_DHCP="false"
    
    read -rp "${TAB}Sync NTP configuration? [y/N]: " SYNC_CONFIG_NTP_INPUT
    SYNC_CONFIG_NTP="${SYNC_CONFIG_NTP_INPUT:-n}"
    [[ "$SYNC_CONFIG_NTP" =~ ^[yY] ]] && SYNC_CONFIG_NTP="true" || SYNC_CONFIG_NTP="false"
    
    read -rp "${TAB}Sync Resolver configuration? [y/N]: " SYNC_CONFIG_RESOLVER_INPUT
    SYNC_CONFIG_RESOLVER="${SYNC_CONFIG_RESOLVER_INPUT:-n}"
    [[ "$SYNC_CONFIG_RESOLVER" =~ ^[yY] ]] && SYNC_CONFIG_RESOLVER="true" || SYNC_CONFIG_RESOLVER="false"
    
    read -rp "${TAB}Sync Database configuration? [y/N]: " SYNC_CONFIG_DATABASE_INPUT
    SYNC_CONFIG_DATABASE="${SYNC_CONFIG_DATABASE_INPUT:-n}"
    [[ "$SYNC_CONFIG_DATABASE" =~ ^[yY] ]] && SYNC_CONFIG_DATABASE="true" || SYNC_CONFIG_DATABASE="false"
    
    read -rp "${TAB}Sync Miscellaneous settings? [y/N]: " SYNC_CONFIG_MISC_INPUT
    SYNC_CONFIG_MISC="${SYNC_CONFIG_MISC_INPUT:-n}"
    [[ "$SYNC_CONFIG_MISC" =~ ^[yY] ]] && SYNC_CONFIG_MISC="true" || SYNC_CONFIG_MISC="false"
    
    read -rp "${TAB}Sync Debug settings? [y/N]: " SYNC_CONFIG_DEBUG_INPUT
    SYNC_CONFIG_DEBUG="${SYNC_CONFIG_DEBUG_INPUT:-n}"
    [[ "$SYNC_CONFIG_DEBUG" =~ ^[yY] ]] && SYNC_CONFIG_DEBUG="true" || SYNC_CONFIG_DEBUG="false"
    
    read -rp "${TAB}Sync DHCP leases? [y/N]: " SYNC_GRAVITY_DHCP_LEASES_INPUT
    SYNC_GRAVITY_DHCP_LEASES="${SYNC_GRAVITY_DHCP_LEASES_INPUT:-n}"
    [[ "$SYNC_GRAVITY_DHCP_LEASES" =~ ^[yY] ]] && SYNC_GRAVITY_DHCP_LEASES="true" || SYNC_GRAVITY_DHCP_LEASES="false"
    
    read -rp "${TAB}Sync Groups? [y/N]: " SYNC_GRAVITY_GROUP_INPUT
    SYNC_GRAVITY_GROUP="${SYNC_GRAVITY_GROUP_INPUT:-n}"
    [[ "$SYNC_GRAVITY_GROUP" =~ ^[yY] ]] && SYNC_GRAVITY_GROUP="true" || SYNC_GRAVITY_GROUP="false"
    
    read -rp "${TAB}Sync Ad Lists? [y/N]: " SYNC_GRAVITY_AD_LIST_INPUT
    SYNC_GRAVITY_AD_LIST="${SYNC_GRAVITY_AD_LIST_INPUT:-n}"
    [[ "$SYNC_GRAVITY_AD_LIST" =~ ^[yY] ]] && SYNC_GRAVITY_AD_LIST="true" || SYNC_GRAVITY_AD_LIST="false"
    
    read -rp "${TAB}Sync Ad Lists by Group? [y/N]: " SYNC_GRAVITY_AD_LIST_BY_GROUP_INPUT
    SYNC_GRAVITY_AD_LIST_BY_GROUP="${SYNC_GRAVITY_AD_LIST_BY_GROUP_INPUT:-n}"
    [[ "$SYNC_GRAVITY_AD_LIST_BY_GROUP" =~ ^[yY] ]] && SYNC_GRAVITY_AD_LIST_BY_GROUP="true" || SYNC_GRAVITY_AD_LIST_BY_GROUP="false"
    
    read -rp "${TAB}Sync Domain Lists? [y/N]: " SYNC_GRAVITY_DOMAIN_LIST_INPUT
    SYNC_GRAVITY_DOMAIN_LIST="${SYNC_GRAVITY_DOMAIN_LIST_INPUT:-n}"
    [[ "$SYNC_GRAVITY_DOMAIN_LIST" =~ ^[yY] ]] && SYNC_GRAVITY_DOMAIN_LIST="true" || SYNC_GRAVITY_DOMAIN_LIST="false"
    
    read -rp "${TAB}Sync Domain Lists by Group? [y/N]: " SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP_INPUT
    SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP="${SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP_INPUT:-n}"
    [[ "$SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP" =~ ^[yY] ]] && SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP="true" || SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP="false"
    
    read -rp "${TAB}Sync Clients? [y/N]: " SYNC_GRAVITY_CLIENT_INPUT
    SYNC_GRAVITY_CLIENT="${SYNC_GRAVITY_CLIENT_INPUT:-n}"
    [[ "$SYNC_GRAVITY_CLIENT" =~ ^[yY] ]] && SYNC_GRAVITY_CLIENT="true" || SYNC_GRAVITY_CLIENT="false"
    
    read -rp "${TAB}Sync Clients by Group? [y/N]: " SYNC_GRAVITY_CLIENT_BY_GROUP_INPUT
    SYNC_GRAVITY_CLIENT_BY_GROUP="${SYNC_GRAVITY_CLIENT_BY_GROUP_INPUT:-n}"
    [[ "$SYNC_GRAVITY_CLIENT_BY_GROUP" =~ ^[yY] ]] && SYNC_GRAVITY_CLIENT_BY_GROUP="true" || SYNC_GRAVITY_CLIENT_BY_GROUP="false"
  fi

  echo ""
  read -rp "${TAB}Sync interval (cron expression, default: 0 */2 * * *): " SYNC_INTERVAL_INPUT
  SYNC_INTERVAL="${SYNC_INTERVAL_INPUT:-0 */2 * * *}"
}

function create_config() {
  msg_info "Creating configuration"
  if [[ -z "$PRIMARY_URL_INPUT" ]] || [[ -z "$PRIMARY_PASSWORD_INPUT" ]] || [[ -z "$REPLICAS_URL_INPUT" ]] || [[ -z "$REPLICAS_PASSWORD_INPUT" ]]; then
    msg_error "Missing required configuration values!"
    exit 1
  fi

  {
    printf "PRIMARY=%s|%s\n" "$PRIMARY_URL_INPUT" "$PRIMARY_PASSWORD_INPUT"
    printf "REPLICAS=%s|%s\n" "$REPLICAS_URL_INPUT" "$REPLICAS_PASSWORD_INPUT"
    printf "CRON=%s\n" "$SYNC_INTERVAL"
    printf "FULL_SYNC=%s\n" "$FULL_SYNC"
    printf "CLIENT_SKIP_TLS_VERIFICATION=true\n"
  } > "$CONFIG_PATH"

  if [[ "$FULL_SYNC" == "false" ]]; then
    cat <<EOF>>"$CONFIG_PATH"
SYNC_CONFIG_DNS=${SYNC_CONFIG_DNS}
SYNC_CONFIG_DHCP=${SYNC_CONFIG_DHCP}
SYNC_CONFIG_NTP=${SYNC_CONFIG_NTP}
SYNC_CONFIG_RESOLVER=${SYNC_CONFIG_RESOLVER}
SYNC_CONFIG_DATABASE=${SYNC_CONFIG_DATABASE}
SYNC_CONFIG_MISC=${SYNC_CONFIG_MISC}
SYNC_CONFIG_DEBUG=${SYNC_CONFIG_DEBUG}
SYNC_GRAVITY_DHCP_LEASES=${SYNC_GRAVITY_DHCP_LEASES}
SYNC_GRAVITY_GROUP=${SYNC_GRAVITY_GROUP}
SYNC_GRAVITY_AD_LIST=${SYNC_GRAVITY_AD_LIST}
SYNC_GRAVITY_AD_LIST_BY_GROUP=${SYNC_GRAVITY_AD_LIST_BY_GROUP}
SYNC_GRAVITY_DOMAIN_LIST=${SYNC_GRAVITY_DOMAIN_LIST}
SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP=${SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP}
SYNC_GRAVITY_CLIENT=${SYNC_GRAVITY_CLIENT}
SYNC_GRAVITY_CLIENT_BY_GROUP=${SYNC_GRAVITY_CLIENT_BY_GROUP}
EOF
  fi

  chmod 600 "$CONFIG_PATH"
  if [[ ! -f "$CONFIG_PATH" ]] || [[ ! -s "$CONFIG_PATH" ]]; then
    msg_error "Failed to create .env file at $CONFIG_PATH"
    exit 1
  fi
  if ! grep -q "^PRIMARY=" "$CONFIG_PATH" || ! grep -q "^REPLICAS=" "$CONFIG_PATH"; then
    msg_error ".env file is missing required variables"
    exit 1
  fi
  msg_ok "Created configuration"
}

function create_wrapper() {
  msg_info "Creating wrapper script"
  cat <<'EOFWRAPPER' >"${INSTALL_PATH}/nebula-sync-wrapper.sh"
#!/bin/bash
set -e
ENV_FILE="/opt/nebula-sync/.env"
BINARY="/opt/nebula-sync/nebula-sync"

if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
      key="${line%%=*}"
      value="${line#*=}"
      export "$key"="$value"
    fi
  done < "$ENV_FILE"
fi

exec "$BINARY" run
EOFWRAPPER
  chmod +x "${INSTALL_PATH}/nebula-sync-wrapper.sh"
  msg_ok "Created wrapper script"
}

function create_service() {
  msg_info "Creating service"
  cat <<EOF>"$SERVICE_PATH"
[Unit]
Description=Nebula-Sync - Pi-hole Configuration Synchronization
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_PATH}
ExecStart=${INSTALL_PATH}/nebula-sync-wrapper.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  msg_info "Verifying service configuration"
  if [[ -f "$CONFIG_PATH" ]]; then
    if grep -q "^PRIMARY=" "$CONFIG_PATH" && grep -q "^REPLICAS=" "$CONFIG_PATH"; then
      msg_ok "Environment variables verified"
    else
      msg_error "Required environment variables (PRIMARY, REPLICAS) not found in $CONFIG_PATH"
      exit 1
    fi
  else
    msg_error ".env file not found at $CONFIG_PATH"
    exit 1
  fi

  systemctl daemon-reload
  enable_service
  msg_ok "Created and started service"
}

function create_update_script() {
  msg_info "Creating update script"
  cat <<'UPDATEEOF' >/usr/local/bin/update_nebula-sync
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
load_functions

INSTALL_PATH="/opt/nebula-sync"
ENV_PATH="/opt/nebula-sync/.env"

if [[ ! -f "$INSTALL_PATH/nebula-sync" ]]; then
  msg_error "Nebula-Sync installation not found!"
  exit 1
fi

msg_info "Stopping service"
if systemctl is-active --quiet nebula-sync.service 2>/dev/null; then
  systemctl stop nebula-sync.service
fi
msg_ok "Stopped service"

msg_info "Backing up configuration"
if [[ -f "$ENV_PATH" ]]; then
  cp "$ENV_PATH" /tmp/nebula-sync.env.bak
  msg_ok "Backed up configuration"
else
  msg_warn "Configuration file not found, skipping backup"
fi

msg_info "Detecting latest Nebula-Sync release"
if check_for_gh_release "nebula-sync" "lovelaze/nebula-sync"; then
  fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "$INSTALL_PATH" "nebula-sync_.*_linux_.*\.tar\.gz"
  LATEST_RELEASE="v$(cat "$HOME/.nebula-sync" 2>/dev/null || echo '0.0.0')"
  msg_ok "Detected Nebula-Sync ${LATEST_RELEASE}"
else
  msg_ok "Nebula-Sync is already up-to-date"
  exit 0
fi

msg_info "Restoring configuration"
if [[ -f /tmp/nebula-sync.env.bak ]]; then
  cp /tmp/nebula-sync.env.bak "$ENV_PATH"
  rm -f /tmp/nebula-sync.env.bak
  msg_ok "Restored configuration"
else
  msg_warn "Backup file not found, keeping existing configuration"
fi

msg_info "Saving version"
echo "${LATEST_RELEASE}" > "/opt/nebula-sync_version.txt"
msg_ok "Saved version"

msg_info "Starting service"
systemctl start nebula-sync.service
msg_ok "Started service"
msg_ok "Updated successfully!"
UPDATEEOF

  chmod +x /usr/local/bin/update_nebula-sync
  msg_ok "Created update script"
}

function install() {
  msg_info "Installing Nebula-Sync"
  mkdir -p "$INSTALL_PATH"
  fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "$INSTALL_PATH" "nebula-sync_.*_linux_.*\.tar\.gz"
  LATEST_RELEASE="v$(cat "$HOME/.nebula-sync" 2>/dev/null || echo '0.0.0')"
  msg_ok "Installed Nebula-Sync"

  gather_config
  create_config
  create_wrapper
  create_service
  create_update_script

  echo "$LATEST_RELEASE" > "/opt/nebula-sync_version.txt"

  echo ""
  msg_ok "${APP} has been installed successfully!"
  echo -e "${TAB}Configuration: ${BL}${CONFIG_PATH}${CL}"
  echo -e "${TAB}View logs: ${BL}journalctl -u nebula-sync -f${CL}"
  echo -e "${TAB}Update with: ${BL}update_nebula-sync${CL}"
}

header_info
detect_os

IP=$(get_ip)

if [[ -f "$BINARY_PATH" ]] || [[ -d "$INSTALL_PATH" && -n "$(ls -A $INSTALL_PATH 2>/dev/null)" ]]; then
  msg_warn "${APP} is already installed."
  echo ""

  echo -n "${TAB}Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update ${APP}? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

msg_warn "${APP} is not installed."
echo ""
echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
