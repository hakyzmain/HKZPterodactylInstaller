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
  case "$OS" in
    ubuntu|debian)
      hkz_rm_log "$(hkz_t rm_nginx_site): /etc/nginx/sites-enabled/pterodactyl.conf"
      rm -f /etc/nginx/sites-enabled/pterodactyl.conf 2>/dev/null || true
      hkz_rm_log "$(hkz_t rm_nginx_site): /etc/nginx/sites-available/pterodactyl.conf"
      rm -f /etc/nginx/sites-available/pterodactyl.conf 2>/dev/null || true
      if [ -f /etc/nginx/sites-available/default ]; then
        hkz_rm_log "$(hkz_t rm_nginx_default): /etc/nginx/sites-enabled/default"
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
      fi
      ;;
    rocky|almalinux)
      hkz_rm_log "$(hkz_t rm_nginx_site): /etc/nginx/conf.d/pterodactyl.conf"
      rm -f /etc/nginx/conf.d/pterodactyl.conf 2>/dev/null || true
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
  rm -f /usr/local/bin/wings 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_stamp_wings): $HKZ_STAMP_WINGS"
  rm -f "$HKZ_STAMP_WINGS" 2>/dev/null || true
  hkz_rm_log "$(hkz_t rm_docker_prune)"
  docker system prune -af 2>/dev/null || true
  msg_ok "$(hkz_t uninstall_ok_wings)"
}

rm_database_ask() {
  [ "$RM_PANEL" != true ] && return 0
  local dbs users
  dbs=$(mariadb -u root -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','performance_schema','mysql','sys');" 2>/dev/null || true)
  [ -z "$dbs" ] && return 0
  echo ""
  echo "  $(hkz_t db_title): $dbs"
  echo -en "  $(hkz_t db_drop_panel) "
  read -r dp
  if [[ "$dp" =~ ^[Yy] ]]; then
    hkz_rm_log "MariaDB: DROP DATABASE panel"
    mariadb -u root -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null || true
    mariadb -u root -e "DROP DATABASE IF EXISTS \`panel\`;" 2>/dev/null || true
  fi
  echo -en "  $(hkz_t db_drop_user) "
  read -r du
  if [[ "$du" =~ ^[Yy] ]]; then
    hkz_rm_log "MariaDB: DROP USER pterodactyl"
    mariadb -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null || true
    mariadb -u root -e "DROP USER IF EXISTS 'pterodactyl'@'localhost';" 2>/dev/null || true
  fi
  mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
}

uninstall_main() {
  detect_os
  [ "$RM_PANEL" = true ] && rm_panel_files
  [ "$RM_WINGS" = true ] && rm_wings_files
  [ "$RM_PANEL" = true ] && rm_database_ask
}

uninstall_main
