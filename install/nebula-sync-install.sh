#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gabriel403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/lovelaze/nebula-sync

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "nebula-sync" "lovelaze/nebula-sync" "prebuild" "latest" "/opt/nebula-sync" "nebula-sync_*_linux_amd64.tar.gz"

msg_info "Creating Configuration"
cat <<'EOF' >/opt/nebula-sync/.env
# ---------------------------------------------------------------------------
# Nebula-Sync configuration
# All settings can be managed here or overwritten by Ansible / config mgmt.
# Restart the service after any change: systemctl restart nebula-sync
# ---------------------------------------------------------------------------

# Required: primary Pi-hole URL and password (format: http://host|password)
PRIMARY=http://pihole-primary.local|changeme

# Required: comma-separated replica Pi-hole URLs with passwords
REPLICAS=http://pihole-replica.local|changeme

# true  = full Teleporter import/export (all settings)
# false = selective sync controlled by SYNC_CONFIG_* / SYNC_GRAVITY_* below
FULL_SYNC=true

# Run gravity update on replicas after sync (default: false)
RUN_GRAVITY=false

# Cron schedule controlling sync frequency (cron format). Required for the
# service to keep running and sync on a schedule; without it, the binary
# syncs once and exits.
CRON=0 * * * *

# Timezone for logs and cron evaluation
TZ=UTC

# ---------------------------------------------------------------------------
# Connection settings (optional)
# ---------------------------------------------------------------------------
# CLIENT_SKIP_TLS_VERIFICATION=false
# CLIENT_RETRY_DELAY_SECONDS=1
# CLIENT_TIMEOUT_SECONDS=20

# ---------------------------------------------------------------------------
# Selective sync (only used when FULL_SYNC=false)
# Set each section to true/false to include or exclude it.
# ---------------------------------------------------------------------------
# SYNC_CONFIG_DNS=true
# SYNC_CONFIG_DHCP=false
# SYNC_CONFIG_NTP=false
# SYNC_CONFIG_RESOLVER=false
# SYNC_CONFIG_DATABASE=false
# SYNC_CONFIG_MISC=false
# SYNC_CONFIG_DEBUG=false
#
# SYNC_GRAVITY_DHCP_LEASES=false
# SYNC_GRAVITY_GROUP=true
# SYNC_GRAVITY_AD_LIST=true
# SYNC_GRAVITY_AD_LIST_BY_GROUP=true
# SYNC_GRAVITY_DOMAIN_LIST=true
# SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP=true
# SYNC_GRAVITY_CLIENT=true
# SYNC_GRAVITY_CLIENT_BY_GROUP=true

# ---------------------------------------------------------------------------
# Config key filters (only used when FULL_SYNC=false)
# Comma-separated key names; INCLUDE and EXCLUDE are mutually exclusive.
# ---------------------------------------------------------------------------
# SYNC_CONFIG_DNS_INCLUDE=upstreams,interface
# SYNC_CONFIG_DNS_EXCLUDE=

# ---------------------------------------------------------------------------
# Webhooks (optional)
# ---------------------------------------------------------------------------
# WEBHOOK_SYNC_SUCCESS_URL=
# WEBHOOK_SYNC_FAILURE_URL=
# WEBHOOK_SYNC_SUCCESS_METHOD=POST
# WEBHOOK_SYNC_FAILURE_METHOD=POST
# WEBHOOK_SYNC_SUCCESS_BODY=
# WEBHOOK_SYNC_FAILURE_BODY=
# WEBHOOK_SYNC_SUCCESS_HEADERS=
# WEBHOOK_SYNC_FAILURE_HEADERS=
# WEBHOOK_CLIENT_SKIP_TLS_VERIFICATION=false
EOF
chmod 600 /opt/nebula-sync/.env
msg_ok "Created Configuration"

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/nebula-sync.service
[Unit]
Description=Nebula-Sync Pi-hole Configuration Sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/opt/nebula-sync/.env
ExecStart=/opt/nebula-sync/nebula-sync run
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now nebula-sync
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
