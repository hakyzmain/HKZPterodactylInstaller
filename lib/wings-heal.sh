#!/bin/bash

hkz_wings_autodeploy_ready() {
  [ -d /etc/pterodactyl ] || return 1
  cd /etc/pterodactyl 2>/dev/null || return 1
  command -v wings >/dev/null 2>&1 || [ -x /usr/local/bin/wings ] || return 1
  return 0
}

hkz_wings_heal() {
  local configs_dir="${1:-}"
  local svc="${configs_dir}/wings.service"
  local cfg

  msg_step "$(hkz_t wings_heal)"
  hkz_ensure_wings_etc
  msg_ok "$(hkz_t wings_heal_etc)"

  if ! hkz_wings_bin >/dev/null 2>&1; then
    hkz_wings_ensure_binary || msg_warn "$(hkz_t wings_heal_no_binary)"
  fi
  if hkz_wings_bin >/dev/null 2>&1; then
    hkz_wings_link_binary
    if [ -f "$svc" ]; then
      cp -f "$svc" /etc/systemd/system/wings.service
      systemctl daemon-reload 2>>"${LOG_PATH:-/dev/null}" || true
      systemctl enable wings 2>>"${LOG_PATH:-/dev/null}" || true
      msg_ok "$(hkz_t wings_heal_service)"
    elif [ -f /etc/systemd/system/wings.service ]; then
      msg_ok "$(hkz_t wings_heal_service)"
    else
      msg_warn "$(hkz_t wings_heal_no_service)"
    fi
    if command -v systemctl >/dev/null 2>&1; then
      systemctl is-active docker >/dev/null 2>&1 || systemctl start docker 2>>"${LOG_PATH:-/dev/null}" || true
    fi
  fi

  if cfg=$(hkz_wings_config_path 2>/dev/null); then
    msg_ok "$(hkz_t wings_heal_config) $cfg"
    hkz_wings_ensure_node_cert || msg_warn "$(hkz_t wings_cert_warn)"
    hkz_wings_start || msg_warn "$(hkz_t wings_heal_start_fail)"
  else
    msg_info "$(hkz_t wings_heal_no_config)"
  fi

  if hkz_wings_autodeploy_ready 2>/dev/null; then
    msg_ok "$(hkz_t wings_heal_deploy_ready)"
  else
    msg_warn "$(hkz_t wings_heal_deploy_not_ready)"
  fi
  msg_info "$(hkz_t wings_deploy_later): phkz wings-deploy"
}
