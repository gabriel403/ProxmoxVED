#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ansible/ansible

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Ansible"
$STD apt install -y \
  ansible \
  git \
  openssh-client
msg_ok "Installed Ansible"

msg_info "Installing community.general Collection"
$STD ansible-galaxy collection install community.general
msg_ok "Installed community.general Collection"

msg_info "Generating SSH Keypair"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -C "ansible-controller"
chmod 600 /root/.ssh/id_ed25519
msg_ok "Generated SSH Keypair"

motd_ssh
customize
cleanup_lxc
