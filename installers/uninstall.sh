#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

RM_PANEL="${RM_PANEL:-true}"
RM_WINGS="${RM_WINGS:-true}"

rm_panel_files() {
  if ! hkz_panel_files_exist; then
    msg_warn "$(hkz_t uninstall_skip_panel)"
    return 0
  fi
  msg_step "$(hkz_t uninstall_panel)"
  hkz_rm_log "$(hkz_t rm_panel_dir): $PANEL_DIR"
  rm -rf "$PANEL_DIR" 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_composer): /usr/local/bin/composer"
  rm -f /usr/local/bin/composer 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_phkz_cli): /usr/local/bin/phkz"
  rm -f /usr/local/bin/phkz 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_cron_update): /etc/cron.d/phkz-panel-update"
  rm -f /etc/cron.d/phkz-panel-update 2>/dev/null || true
  hkz_cleanup_panel_nginx_sites
  case "$OS" in
    ubuntu|debian)
      if [ -f /etc/nginx/sites-available/default ]; then
        hkz_rm_log "$(hkz_t rm_nginx_default): /etc/nginx/sites-enabled/default"
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
      fi
      ;;
  esac
  hkz_rm_log "$(hkz_t rm_pteroq_stop)"
  systemctl disable --now pteroq 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_pteroq_unit): /etc/systemd/system/pteroq.service"
  rm -f /etc/systemd/system/pteroq.service 2>/dev/null || true
  for u in www-data nginx; do
    hkz_rm_log "$(hkz_t rm_crontab_schedule): $u"
    crontab -u "$u" -l 2>/dev/null | grep -v 'schedule:run' | crontab -u "$u" - 2>/dev/null || true
  done
  hkz_rm_log "$(hkz_t rm_stamp_panel): $HKZ_STAMP_PANEL"
  rm -f "$HKZ_STAMP_PANEL" 2>/dev/null || true
  hkz_panel_clear_install_secrets
  hkz_rm_log "$(hkz_t rm_nginx_reload)"
  systemctl reload nginx 2>/dev/null || true
  msg_ok "$(hkz_t uninstall_ok_panel)"
}

rm_wings_files() {
  if ! hkz_wings_files_exist; then
    msg_warn "$(hkz_t uninstall_skip_wings)"
    return 0
  fi
  msg_step "$(hkz_t uninstall_wings)"
  hkz_rm_log "$(hkz_t rm_wings_stop)"
  systemctl disable --now wings 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_wings_unit): /etc/systemd/system/wings.service"
  rm -f /etc/systemd/system/wings.service 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_wings_etc)"
  rm -rf /etc/pterodactyl 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_wings_lib)"
  rm -rf /var/lib/pterodactyl 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_wings_bin): /usr/local/bin/wings"
  rm -f /usr/local/bin/wings /usr/bin/wings 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_stamp_wings): $HKZ_STAMP_WINGS"
  rm -f "$HKZ_STAMP_WINGS" 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_docker_prune)"
  docker system prune -af 2>/dev/null || true
  msg_ok "$(hkz_t uninstall_ok_wings)"
}

rm_database_ask() {
  [ "$RM_PANEL" != true ] && return 0
  local dbs users ans
  hkz_ensure_mariadb_running 2>/dev/null || true
  hkz_mysql_bin >/dev/null 2>&1 || {
    msg_info "$(hkz_t db_no_mysql)"
    hkz_cleanup_panel_redis ask || true
    return 0
  }

  dbs=$(hkz_collect_ptero_databases 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  users=$(hkz_collect_ptero_db_users 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')

  echo ""
  if [ -n "$dbs" ]; then
    msg_info "$(hkz_t db_found): $dbs"
  else
    msg_info "$(hkz_t db_none)"
  fi
  if [ -n "$users" ]; then
    msg_info "$(hkz_t db_users_found): $users"
  fi

  if [ -n "$dbs" ] || [ -n "$users" ]; then
    echo -en "  $(hkz_t db_drop_all) "
    read -r ans
    if [[ ! "$ans" =~ ^[Nn] ]]; then
      [ -n "$dbs" ] && hkz_drop_databases $dbs
      [ -n "$users" ] && hkz_drop_db_users $users
      msg_ok "$(hkz_t db_drop_ok)"
    fi
  fi

  hkz_cleanup_panel_redis ask || true
}

uninstall_main() {
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  [ "$RM_PANEL" = true ] && rm_panel_files
  [ "$RM_WINGS" = true ] && rm_wings_files
  [ "$RM_PANEL" = true ] && rm_database_ask
}

uninstall_main
