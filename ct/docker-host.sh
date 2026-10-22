#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gabriel403)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.docker.com/

APP="Docker-Host"
var_tags="${var_tags:-docker}"
# Also the floor check_container_resources holds every update to, and an
# unattended update below it aborts: keep these at the smallest Docker host.
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v docker &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Docker's apt repo is configured, so this also upgrades Docker. Not
  # setup_docker: on an interactive run it pulls every running container's
  # image and offers to recreate it, and the stacks here are owned elsewhere.
  msg_info "Updating Docker-Host"
  apt_update_safe
  $STD apt -y upgrade
  msg_ok "Updated Docker-Host"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Docker Engine and the Compose plugin are ready; no stacks are installed.${CL}"
