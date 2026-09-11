#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://git-core-1.internal.g403.co/gabriel/g403-ddns

APP="g403-ddns"
var_tags="${var_tags:-network;ddns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Application settings - prompted for inside the container when unset.
export var_repo_url="${var_repo_url:-https://git-core-1.internal.g403.co/gabriel/g403-ddns.git}"
export var_ip_source="${var_ip_source:-}"
export var_omada_url="${var_omada_url:-}"
export var_omada_client_id="${var_omada_client_id:-}"
export var_omada_client_secret="${var_omada_client_secret:-}"
export var_omada_site="${var_omada_site:-}"
export var_cf_api_token="${var_cf_api_token:-}"
export var_cf_record="${var_cf_record:-}"
export var_cf_zone="${var_cf_zone:-}"
export var_interval="${var_interval:-}"

header_info "$APP"
variables
color
catch_errors

if [[ -n "${mode:-}" ]]; then
  for required in var_cf_api_token var_cf_record; do
    if [[ -z "${!required:-}" ]]; then
      msg_error "${required} is required for unattended installs."
      exit 1
    fi
  done
  if [[ "${var_ip_source:-omada}" == "omada" ]]; then
    for required in var_omada_url var_omada_client_id var_omada_client_secret; do
      if [[ -z "${!required:-}" ]]; then
        msg_error "${required} is required for unattended installs with var_ip_source=omada."
        exit 1
      fi
    done
  fi
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/g403-ddns/.git ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  cd /opt/g403-ddns
  $STD git fetch -q origin
  if [[ "$(git rev-parse HEAD)" == "$(git rev-parse '@{u}')" ]]; then
    msg_ok "No update required. ${APP} is already at $(git rev-parse --short HEAD)."
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop g403-ddns
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  $STD git reset -q --hard '@{u}'
  msg_ok "Updated ${APP} to $(git rev-parse --short HEAD)"

  msg_info "Starting Service"
  systemctl start g403-ddns
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Health endpoint (200 = last cycle succeeded, 503 = failing):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} Config lives in /opt/g403-ddns/.env - edit and 'systemctl restart g403-ddns'.${CL}"
