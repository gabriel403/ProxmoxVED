#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://git-core-1.internal.g403.co/gabriel/g403-ddns

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

msg_info "Fetching g403-ddns"
$STD git clone -q "${var_repo_url:-https://git-core-1.internal.g403.co/gabriel/g403-ddns.git}" /opt/g403-ddns
msg_ok "Fetched g403-ddns $(git -C /opt/g403-ddns rev-parse --short HEAD)"

# ---------------------------------------------------------------------------
# Gather configuration. Every prompt is skipped when the matching var_* is
# already set (exported from ct/g403-ddns.sh), so unattended installs work.
# ---------------------------------------------------------------------------
echo
echo -e "${TAB3}${BOLD}Where should the WAN IP come from?${CL}"
echo -e "${TAB3}  omada  - read the gateway's WAN port from the Omada controller (default)"
echo -e "${TAB3}  public - ask 1.1.1.1 what IP this container appears from (use behind double NAT)"
if [[ -z "${var_ip_source:-}" ]]; then
  read -r -p "${TAB3}IP source [omada]: " var_ip_source
fi
var_ip_source="${var_ip_source:-omada}"
if [[ "$var_ip_source" != "omada" && "$var_ip_source" != "public" ]]; then
  msg_error "IP source must be 'omada' or 'public', got '${var_ip_source}'"
  exit 1
fi

if [[ "$var_ip_source" == "omada" ]]; then
  echo
  echo -e "${TAB3}${BOLD}Omada controller${CL}"
  echo -e "${TAB3}The URL this container will use to reach the controller, e.g. https://omada.lan:8043"
  echo -e "${TAB3}Needs controller 5.9 or newer for the Open API."
  if [[ -z "${var_omada_url:-}" ]]; then
    read -r -p "${TAB3}Controller URL: " var_omada_url
  fi
  echo
  echo -e "${TAB3}Create an Open API client in the controller:"
  echo -e "${TAB3}  Global View > Settings > Platform Integration > Open API > Add New App"
  echo -e "${TAB3}  Mode: Client Credentials   Role: Viewer (read-only is enough)"
  echo -e "${TAB3}The Client ID and Client Secret are shown once the app is created."
  if [[ -z "${var_omada_client_id:-}" ]]; then
    read -r -p "${TAB3}Client ID: " var_omada_client_id
  fi
  if [[ -z "${var_omada_client_secret:-}" ]]; then
    read -r -s -p "${TAB3}Client Secret (hidden): " var_omada_client_secret
    echo
  fi
  echo
  echo -e "${TAB3}Site name as shown in the controller's site picker."
  echo -e "${TAB3}Leave empty if the controller only has one site."
  if [[ -z "${var_omada_site:-}" ]]; then
    read -r -p "${TAB3}Site name []: " var_omada_site
  fi
  for required in var_omada_url var_omada_client_id var_omada_client_secret; do
    if [[ -z "${!required:-}" ]]; then
      msg_error "${required#var_} is required when the IP source is omada"
      exit 1
    fi
  done
fi

echo
echo -e "${TAB3}${BOLD}Cloudflare${CL}"
echo -e "${TAB3}Create a token at https://dash.cloudflare.com/profile/api-tokens"
echo -e "${TAB3}  Create Token > template 'Edit zone DNS'"
echo -e "${TAB3}  Zone Resources: Include > Specific zone > the zone that holds the record"
echo -e "${TAB3}Copy it straight away - Cloudflare only shows it once."
if [[ -z "${var_cf_api_token:-}" ]]; then
  read -r -s -p "${TAB3}API token (hidden): " var_cf_api_token
  echo
fi
echo
echo -e "${TAB3}The full DNS name to keep updated, e.g. vpn.example.com."
echo -e "${TAB3}It is created as an A record if it does not exist yet."
if [[ -z "${var_cf_record:-}" ]]; then
  read -r -p "${TAB3}Record name: " var_cf_record
fi
echo
echo -e "${TAB3}Zone name (e.g. example.com). Leave empty to derive it from the record."
if [[ -z "${var_cf_zone:-}" ]]; then
  read -r -p "${TAB3}Zone name []: " var_cf_zone
fi
for required in var_cf_api_token var_cf_record; do
  if [[ -z "${!required:-}" ]]; then
    msg_error "${required#var_} is required"
    exit 1
  fi
done

echo
if [[ -z "${var_interval:-}" ]]; then
  read -r -p "${TAB3}Check interval in seconds [60]: " var_interval
fi
var_interval="${var_interval:-60}"
echo

msg_info "Writing Configuration"
cat <<EOF >/opt/g403-ddns/.env
IP_SOURCE=${var_ip_source}
INTERVAL_SECONDS=${var_interval}
HEALTH_PORT=8080
OMADA_URL=${var_omada_url:-}
OMADA_CLIENT_ID=${var_omada_client_id:-}
OMADA_CLIENT_SECRET=${var_omada_client_secret:-}
OMADA_OMADAC_ID=
OMADA_SITE=${var_omada_site:-}
OMADA_GATEWAY_MAC=
OMADA_WAN_PORT=
OMADA_TLS_VERIFY=true
CF_API_TOKEN=${var_cf_api_token}
CF_RECORD_NAME=${var_cf_record}
CF_ZONE_NAME=${var_cf_zone:-}
CF_TTL=60
CF_PROXIED=false
EOF
chmod 600 /opt/g403-ddns/.env
msg_ok "Wrote Configuration to /opt/g403-ddns/.env"

msg_info "Checking Credentials (dry run, changes nothing)"
if (cd /opt/g403-ddns && HEALTH_PORT=0 node --env-file=.env src/index.ts --once --dry-run); then
  msg_ok "Checked Credentials"
else
  msg_error "Credential check failed - see the lines above. The service is still installed; fix /opt/g403-ddns/.env and 'systemctl restart g403-ddns'."
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/g403-ddns.service
[Unit]
Description=g403-ddns - Omada WAN IP to Cloudflare DNS
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/g403-ddns
EnvironmentFile=/opt/g403-ddns/.env
ExecStart=/usr/bin/node /opt/g403-ddns/src/index.ts
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now g403-ddns
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
