#!/usr/bin/env bash

# Copyright (c) 2023-2026 community-scripts ORG
# Author: MickLesk | Maintainer: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.proxmox.com/

function header_info {
  clear
  cat <<"EOF"
  ____                            _                        ____ _               _    
 |  _ \  ___ _ __   ___ _ __   __| | ___ _ __   ___ _   _ / ___| |__   ___  ___| | __
 | | | |/ _ \ '_ \ / _ \ '_ \ / _` |/ _ \ '_ \ / __| | | | |   | '_ \ / _ \/ __| |/ /
 | |_| |  __/ |_) |  __/ | | | (_| |  __/ | | | (__| |_| | |___| | | |  __/ (__|   < 
 |____/ \___| .__/ \___|_| |_|\__,_|\___|_| |_|\___|\__, |\____|_| |_|\___|\___|_|\_\
            |_|                                     |___/                            
EOF
}

YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"

msg_info() {
  local msg="$1"
  echo -e "${INFO} ${YW}${msg}...${CL}"
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

SCRIPT_NAME="$(basename "$0")"
HOOKSCRIPT_FILE="/var/lib/vz/snippets/dependency-check.sh"
HOOKSCRIPT_VOLUME_ID="local:snippets/dependency-check.sh"
CONFIG_FILE="/etc/default/pve-auto-hook"
APPLICATOR_FILE="/usr/local/bin/pve-apply-hookscript.sh"
PATH_UNIT_FILE="/etc/systemd/system/pve-auto-hook.path"
SERVICE_UNIT_FILE="/etc/systemd/system/pve-auto-hook.service"

function print_usage {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Install or remove the Proxmox startup dependency-check hook system.

Options:
  --install       Install/update hookscript automation (default)
  --uninstall     Remove automation and cleanup hookscript assignments
  --status        Show current installation state
  --help, -h      Show this help message
EOF
}

function ensure_supported_pve {
  if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
  fi

  local pve_version major
  pve_version=$(pveversion | grep -oE 'pve-manager/[0-9.]+' | cut -d'/' -f2)
  major=$(echo "$pve_version" | cut -d'.' -f1)

  if [[ -z "$major" ]] || ! [[ "$major" =~ ^[0-9]+$ ]]; then
    msg_error "Unable to detect a supported Proxmox version"
    exit 1
  fi

  if [[ "$major" -lt 8 ]] || [[ "$major" -gt 9 ]]; then
    msg_error "Supported on Proxmox VE 8.x and 9.x (detected: $pve_version)"
    exit 1
  fi

  msg_ok "Proxmox VE $pve_version detected"
}

function confirm_action {
  local prompt="$1"
  read -r -p "$prompt (y/n): " -n 1 REPLY
  echo
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

create_dependency_hookscript() {
  msg_info "Creating dependency-check hookscript"
  mkdir -p /var/lib/vz/snippets
  cat <<'EOF' >/var/lib/vz/snippets/dependency-check.sh
#!/bin/bash
# Proxmox Hookscript for Pre-Start Dependency Checking
# Works for both QEMU VMs and LXC Containers

POLL_INTERVAL=5       # Seconds to wait between checks
MAX_ATTEMPTS=60       # Max number of attempts before failing (60 * 5s = 5 minutes)

VMID=$1
PHASE=$2

log() {
    logger -t hookscript-dep-check "VMID $VMID: $1"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_tcp() {
    local host="$1"
    local port="$2"

    if has_cmd nc; then
        nc -z -w 2 "$host" "$port" >/dev/null 2>&1
        return $?
    fi

    timeout 2 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
}

wait_until() {
    local description="$1"
    local check_cmd="$2"

    local attempts=0
    while true; do
        if eval "$check_cmd"; then
            log "$description"
            return 0
        fi

        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
            log "ERROR: Timeout waiting for condition: $description"
            return 1
        fi

        log "Waiting ${POLL_INTERVAL}s for condition: $description (Attempt ${attempts}/${MAX_ATTEMPTS})"
        sleep "$POLL_INTERVAL"
    done
}

if [ "$PHASE" != "pre-start" ]; then
    exit 0
fi

log "--- Starting Pre-Start Dependency Check ---"

if qm config "$VMID" >/dev/null 2>&1; then
    CONFIG_CMD=(qm config "$VMID")
    log "Guest type is QEMU (VM)."
elif pct config "$VMID" >/dev/null 2>&1; then
    CONFIG_CMD=(pct config "$VMID")
    log "Guest type is LXC (Container)."
else
    log "ERROR: Could not determine guest type for $VMID. Aborting."
    exit 1
fi

GUEST_CONFIG=$("${CONFIG_CMD[@]}")

log "Checking storage availability..."
STORAGE_IDS=$(echo "$GUEST_CONFIG" | awk -F':' '
    /^(scsi|sata|virtio|ide|efidisk|tpmstate|unused|rootfs|mp)[0-9]*:/ {
        val=$2
        gsub(/^[[:space:]]+/, "", val)
        split(val, parts, ",")
        storage=parts[1]

        # Skip bind-mount style paths and empty values
        if (storage == "" || storage ~ /^\//) next

        print storage
    }
' | sort -u)

if [ -z "$STORAGE_IDS" ]; then
    log "No storage dependencies found to check."
else
    for STORAGE_ID in $STORAGE_IDS; do
        STATUS=$(pvesm status 2>/dev/null | awk -v id="$STORAGE_ID" '$1 == id { print $3; exit }')

        if [ -z "$STATUS" ]; then
            log "WARNING: Storage '$STORAGE_ID' not found in 'pvesm status'. Skipping this dependency."
            continue
        fi

        wait_until "Storage '$STORAGE_ID' is active." "[ \"\$(pvesm status 2>/dev/null | awk -v id=\"$STORAGE_ID\" '\$1 == id { print \$3; exit }')\" = \"active\" ]" || exit 1
    done
fi
log "All storage dependencies are met."

log "Checking for custom tag-based dependencies..."
TAGS=$(echo "$GUEST_CONFIG" | awk -F': ' '/^tags:/ {print $2}')

if [ -z "$TAGS" ]; then
    log "No tags found. Skipping custom dependency check."
else
    for TAG in ${TAGS//;/ }; do
        if [[ $TAG == dep_* ]]; then
            log "Found dependency tag: '$TAG'"

            IFS='_' read -r _ DEP_TYPE HOST PORT EXTRA <<< "$TAG"

            case "$DEP_TYPE" in
                ping)
                    if [ -z "$HOST" ]; then
                        log "WARNING: Malformed ping dependency tag '$TAG'. Ignoring."
                        continue
                    fi
                    wait_until "Ping dependency met: Host $HOST is reachable." "ping -c 1 -W 2 \"$HOST\" >/dev/null 2>&1" || exit 1
                    ;;
                tcp)
                    if [ -z "$HOST" ] || [ -z "$PORT" ] || ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
                        log "WARNING: Malformed TCP dependency tag '$TAG'. Expected dep_tcp_<host>_<port>. Ignoring."
                        continue
                    fi
                    wait_until "TCP dependency met: Host $HOST port $PORT is open." "check_tcp \"$HOST\" \"$PORT\"" || exit 1
                    ;;
                *)
                    log "WARNING: Unknown dependency type '$DEP_TYPE' in tag '$TAG'. Ignoring."
                    ;;
            esac
        fi
    done
fi

log "All custom dependencies are met."
log "--- Dependency Check Complete. Proceeding with start. ---"
exit 0
EOF
  chmod +x "$HOOKSCRIPT_FILE"
  msg_ok "Created dependency-check hookscript"
}

create_exclusion_config() {
  msg_info "Creating exclusion configuration file"
  if [ -f "$CONFIG_FILE" ]; then
    msg_ok "Exclusion file already exists, skipping."
  else
    cat <<'EOF' >/etc/default/pve-auto-hook
#
# Configuration for the Proxmox Automatic Hookscript Applicator
#
# Add VM or LXC IDs here to prevent the hookscript from being added.
# Separate IDs with spaces.
#
# Example:
# IGNORE_IDS="9000 9001 105"
#

IGNORE_IDS=""
EOF
    chmod 0644 "$CONFIG_FILE"
    msg_ok "Created exclusion configuration file"
  fi
}

create_applicator_script() {
  msg_info "Creating the hookscript applicator script"
  cat <<'EOF' >/usr/local/bin/pve-apply-hookscript.sh
#!/bin/bash
HOOKSCRIPT_VOLUME_ID="local:snippets/dependency-check.sh"
CONFIG_FILE="/etc/default/pve-auto-hook"
LOG_TAG="pve-auto-hook"
IGNORE_IDS=""

log() {
    systemd-cat -t "$LOG_TAG" <<< "$1"
}

if [ -f "$CONFIG_FILE" ]; then
    IGNORE_IDS=$(grep -E '^IGNORE_IDS=' "$CONFIG_FILE" | head -n1 | cut -d'=' -f2- | tr -d '"')
fi

is_ignored() {
    local vmid="$1"
    for id_to_ignore in $IGNORE_IDS; do
        if [ "$id_to_ignore" = "$vmid" ]; then
            return 0
        fi
    done
    return 1
}

ensure_hookscript() {
    local guest_type="$1"
    local vmid="$2"
    local current_hook=""

    if [ "$guest_type" = "qemu" ]; then
        current_hook=$(qm config "$vmid" | awk '/^hookscript:/ {print $2}')
    else
        current_hook=$(pct config "$vmid" | awk '/^hookscript:/ {print $2}')
    fi

    if [ -n "$current_hook" ]; then
        if [ "$current_hook" = "$HOOKSCRIPT_VOLUME_ID" ]; then
            return 0
        fi
        log "Guest $guest_type/$vmid already has another hookscript ($current_hook). Leaving unchanged."
        return 0
    fi

    log "Applying hookscript to $guest_type/$vmid"
    if [ "$guest_type" = "qemu" ]; then
        qm set "$vmid" --hookscript "$HOOKSCRIPT_VOLUME_ID" >/dev/null 2>&1
    else
        pct set "$vmid" --hookscript "$HOOKSCRIPT_VOLUME_ID" >/dev/null 2>&1
    fi
}

qm list | awk 'NR>1 {print $1}' | while read -r VMID; do
    if is_ignored "$VMID"; then
        continue
    fi
    ensure_hookscript "qemu" "$VMID"
done

pct list | awk 'NR>1 {print $1}' | while read -r VMID; do
    if is_ignored "$VMID"; then
        continue
    fi
    ensure_hookscript "lxc" "$VMID"
done
EOF
  chmod +x "$APPLICATOR_FILE"
  msg_ok "Created applicator script"
}

create_systemd_units() {
  msg_info "Creating systemd watcher and service units"
  cat <<'EOF' >/etc/systemd/system/pve-auto-hook.path
[Unit]
Description=Watch for new Proxmox guest configs to apply hookscript

[Path]
PathExistsGlob=/etc/pve/qemu-server/*.conf
PathExistsGlob=/etc/pve/lxc/*.conf
Unit=pve-auto-hook.service

[Install]
WantedBy=multi-user.target
EOF

  cat <<'EOF' >/etc/systemd/system/pve-auto-hook.service
[Unit]
Description=Automatically add hookscript to new Proxmox guests

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pve-apply-hookscript.sh
EOF
  chmod 0644 "$PATH_UNIT_FILE" "$SERVICE_UNIT_FILE"
  msg_ok "Created systemd units"
}

remove_hookscript_assignments() {
  msg_info "Removing hookscript assignment from guests using dependency-check"

  qm list | awk 'NR>1 {print $1}' | while read -r vmid; do
    current_hook=$(qm config "$vmid" | awk '/^hookscript:/ {print $2}')
    if [ "$current_hook" = "$HOOKSCRIPT_VOLUME_ID" ]; then
      qm set "$vmid" --delete hookscript >/dev/null 2>&1 && msg_ok "Removed hookscript from VM $vmid"
    fi
  done

  pct list | awk 'NR>1 {print $1}' | while read -r vmid; do
    current_hook=$(pct config "$vmid" | awk '/^hookscript:/ {print $2}')
    if [ "$current_hook" = "$HOOKSCRIPT_VOLUME_ID" ]; then
      pct set "$vmid" --delete hookscript >/dev/null 2>&1 && msg_ok "Removed hookscript from LXC $vmid"
    fi
  done
}

install_stack() {
  create_dependency_hookscript
  create_exclusion_config
  create_applicator_script
  create_systemd_units

  msg_info "Reloading systemd and enabling watcher"
  if systemctl daemon-reload && systemctl enable --now pve-auto-hook.path >/dev/null 2>&1; then
    msg_ok "Systemd watcher enabled and running"
  else
    msg_error "Could not enable pve-auto-hook.path"
    exit 1
  fi

  msg_info "Performing initial run to update existing guests"
  if "$APPLICATOR_FILE" >/dev/null 2>&1; then
    msg_ok "Initial run complete"
  else
    msg_error "Initial run failed"
    exit 1
  fi
}

uninstall_stack() {
  remove_hookscript_assignments

  msg_info "Stopping and disabling systemd units"
  systemctl disable --now pve-auto-hook.path >/dev/null 2>&1 || true
  systemctl disable --now pve-auto-hook.service >/dev/null 2>&1 || true

  msg_info "Removing installed files"
  rm -f "$HOOKSCRIPT_FILE" "$APPLICATOR_FILE" "$PATH_UNIT_FILE" "$SERVICE_UNIT_FILE" "$CONFIG_FILE"

  if systemctl daemon-reload >/dev/null 2>&1; then
    msg_ok "systemd daemon reloaded"
  else
    msg_error "Failed to reload systemd daemon"
    exit 1
  fi

  msg_ok "Dependency-check stack successfully removed"
}

show_status() {
  echo -e "\n${BL}Dependency-check status${CL}"
  echo -e "--------------------------------"
  [ -f "$HOOKSCRIPT_FILE" ] && echo -e "Hookscript file:   ${GN}present${CL}" || echo -e "Hookscript file:   ${RD}missing${CL}"
  [ -f "$APPLICATOR_FILE" ] && echo -e "Applicator script: ${GN}present${CL}" || echo -e "Applicator script: ${RD}missing${CL}"
  [ -f "$CONFIG_FILE" ] && echo -e "Config file:       ${GN}present${CL}" || echo -e "Config file:       ${RD}missing${CL}"
  [ -f "$PATH_UNIT_FILE" ] && echo -e "Path unit:         ${GN}present${CL}" || echo -e "Path unit:         ${RD}missing${CL}"
  [ -f "$SERVICE_UNIT_FILE" ] && echo -e "Service unit:      ${GN}present${CL}" || echo -e "Service unit:      ${RD}missing${CL}"

  if systemctl is-enabled pve-auto-hook.path >/dev/null 2>&1; then
    echo -e "Watcher enabled:   ${GN}yes${CL}"
  else
    echo -e "Watcher enabled:   ${YW}no${CL}"
  fi

  if systemctl is-active pve-auto-hook.path >/dev/null 2>&1; then
    echo -e "Watcher active:    ${GN}yes${CL}"
  else
    echo -e "Watcher active:    ${YW}no${CL}"
  fi
}

header_info
ensure_supported_pve

case "${1:---install}" in
--help | -h)
  print_usage
  exit 0
  ;;
--status)
  show_status
  exit 0
  ;;
--install)
  echo -e "\nThis script will install a service to automatically apply a"
  echo -e "dependency-checking hookscript to all new and existing Proxmox guests."
  echo -e "${YW}This includes creating files in:${CL}"
  echo -e "  - /var/lib/vz/snippets/"
  echo -e "  - /usr/local/bin/"
  echo -e "  - /etc/default/"
  echo -e "  - /etc/systemd/system/\n"

  if ! confirm_action "Do you want to proceed with the installation?"; then
    msg_error "Installation cancelled"
    exit 1
  fi

  echo ""
  install_stack

  echo -e "\n${GN}Installation successful!${CL}"
  echo -e "The service is now active and will monitor for new guests."
  echo -e "To ${YW}exclude${CL} a VM or LXC, add its ID to ${YW}IGNORE_IDS${CL} in:"
  echo -e "  ${YW}${CONFIG_FILE}${CL}"
  echo -e "\nMonitor activity with:"
  echo -e "  ${YW}journalctl -fu pve-auto-hook.service${CL}\n"
  ;;
--uninstall)
  echo -e "\nThis will completely remove the dependency-check stack:"
  echo -e "  - hookscript and applicator"
  echo -e "  - systemd path/service units"
  echo -e "  - exclusion config"
  echo -e "  - hookscript assignment from guests using ${HOOKSCRIPT_VOLUME_ID}\n"

  if ! confirm_action "Do you want to proceed with uninstall?"; then
    msg_error "Uninstall cancelled"
    exit 1
  fi

  echo ""
  uninstall_stack
  ;;
*)
  msg_error "Unknown option: $1"
  print_usage
  exit 1
  ;;
esac

exit 0
