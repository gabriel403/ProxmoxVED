#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gabriel403)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.docker.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# setup_docker writes daemon.json only when none exists, and defaults to the
# journald driver, which puts every container line in the journal as well as
# Docker's own log, so a log agent reading both collects it twice.
msg_info "Configuring Docker Logging"
mkdir -p /etc/docker
cat <<EOF >/etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "20m", "max-file": "3"}
}
EOF
msg_ok "Configured Docker Logging"

setup_docker

motd_ssh
customize
cleanup_lxc
