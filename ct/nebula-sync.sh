#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gabriel403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/lovelaze/nebula-sync

APP="Nebula-Sync"
var_tags="${var_tags:-pihole;sync;dns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-128}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/nebula-sync/nebula-sync ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nebula-sync" "lovelaze/nebula-sync"; then
    msg_info "Stopping Service"
    systemctl stop nebula-sync.timer nebula-sync.service
    msg_ok "Stopped Service"

    create_backup /opt/nebula-sync/.env

    fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "/opt/nebula-sync" "nebula-sync_*_linux_amd64.tar.gz"

    restore_backup

    msg_info "Starting Service"
    systemctl start nebula-sync.timer
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Configure your Pi-hole credentials in:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/nebula-sync/.env${CL}"
echo -e "${INFO}${YW} Then restart the timer:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}systemctl restart nebula-sync.timer${CL}"
