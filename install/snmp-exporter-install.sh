#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/prometheus/snmp_exporter

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "snmp_exporter" "prometheus/snmp_exporter" "prebuild" "latest" "/opt/snmp_exporter" "snmp_exporter-*.linux-amd64.tar.gz"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/snmp_exporter.service
[Unit]
Description=Prometheus SNMP Exporter
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/snmp_exporter
ExecStart=/opt/snmp_exporter/snmp_exporter --config.file=/opt/snmp_exporter/snmp.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now snmp_exporter
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc