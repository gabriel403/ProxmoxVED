#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/prometheus/snmp_exporter

APP="SNMP-Exporter"
var_tags="${var_tags:-monitoring;prometheus}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
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

  if [[ ! -d /opt/snmp_exporter ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "snmp_exporter" "prometheus/snmp_exporter"; then
    msg_info "Stopping ${APP}"
    systemctl stop snmp_exporter
    msg_ok "Stopped ${APP}"

    msg_info "Backing up snmp.yml"
    cp /opt/snmp_exporter/snmp.yml /opt/snmp_exporter/snmp.yml.bak
    msg_ok "Backed up snmp.yml"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "snmp_exporter" "prometheus/snmp_exporter" "prebuild" "latest" "/opt/snmp_exporter" "snmp_exporter-*.linux-amd64.tar.gz"

    msg_info "Restoring snmp.yml"
    mv /opt/snmp_exporter/snmp.yml.bak /opt/snmp_exporter/snmp.yml
    msg_ok "Restored snmp.yml"

    msg_info "Starting ${APP}"
    systemctl start snmp_exporter
    msg_ok "Started ${APP}"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9116${CL}"