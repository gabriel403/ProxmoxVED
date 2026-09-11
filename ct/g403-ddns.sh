#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/gabriel403/ProxmoxVED/tree/add-g403-ddns/tools/g403-ddns

APP="g403-ddns"
var_tags="${var_tags:-network;ddns}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Application settings - prompted for inside the container when unset.
export var_source_url="${var_source_url:-https://raw.githubusercontent.com/gabriel403/ProxmoxVED/add-g403-ddns/tools/g403-ddns/index.ts}"
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

# The install prompts for credentials it was not given. Prompts read the
# terminal that lxc-attach inherits from this process, so a piped entry
# (curl ... | bash) hands them EOF and the build fails after minutes of work.
# Catch that here, before anything is built.
_g403_missing=()
for required in var_cf_api_token var_cf_record; do
  [[ -z "${!required:-}" ]] && _g403_missing+=("$required")
done
if [[ "${var_ip_source:-omada}" == "omada" ]]; then
  for required in var_omada_url var_omada_client_id var_omada_client_secret; do
    [[ -z "${!required:-}" ]] && _g403_missing+=("$required")
  done
fi
if [[ ${#_g403_missing[@]} -gt 0 && ! -t 0 && -z "${mode:-}" ]]; then
  msg_error "stdin is not a terminal, so the install could not prompt for: ${_g403_missing[*]}"
  msg_error "Run it as: bash <(curl -fsSL <core>/tools/run.sh) <script-base> ct/g403-ddns.sh"
  msg_error "or pass those as var_* environment variables."
  exit 1
fi

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

  if [[ ! -f /opt/g403-ddns/index.ts ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for Update"
  curl -fsSL "${var_source_url}" -o /opt/g403-ddns/index.ts.new
  if cmp -s /opt/g403-ddns/index.ts /opt/g403-ddns/index.ts.new; then
    rm -f /opt/g403-ddns/index.ts.new
    msg_ok "No update required. ${APP} is already at $(sha256sum /opt/g403-ddns/index.ts | cut -c1-12)."
    exit
  fi
  msg_ok "Found Update"

  msg_info "Stopping Service"
  systemctl stop g403-ddns
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  mv /opt/g403-ddns/index.ts.new /opt/g403-ddns/index.ts
  msg_ok "Updated ${APP} to $(sha256sum /opt/g403-ddns/index.ts | cut -c1-12)"

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
