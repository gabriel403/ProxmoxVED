#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ansible/ansible

APP="Ansible"
var_tags="${var_tags:-ansible;automation;devops}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v ansible &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  INSTALLED=$(dpkg -s ansible 2>/dev/null | awk '/^Version:/{print $2}')
  $STD apt update
  LATEST=$(apt-cache policy ansible 2>/dev/null | awk '/Candidate:/{print $2}')

  if [[ "${INSTALLED}" == "${LATEST}" ]]; then
    msg_ok "Already on the latest version (${INSTALLED})"
  else
    msg_info "Updating Ansible to ${LATEST}"
    $STD apt install --only-upgrade -y ansible
    msg_ok "Updated Ansible to ${LATEST}"
  fi

  msg_info "Updating community.general Collection"
  $STD ansible-galaxy collection install community.general --upgrade
  msg_ok "Updated community.general Collection"

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Add this SSH public key to each PVE host's ansible user:${CL}"
echo -e "${TAB}${BGN}$(pct exec ${CTID} -- cat /root/.ssh/id_ed25519.pub 2>/dev/null || true)${CL}"
