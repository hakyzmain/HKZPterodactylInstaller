#!/bin/bash

run_info() {
  msg_step "$(hkz_t info_title)"
  hkz_panel_report_detect 2>/dev/null || true
  hkz_wings_files_exist && msg_info "$(hkz_t detect_wings_ok)"
  local ok=0 fail=0
  check_one() {
    if eval "$2" >/dev/null 2>&1; then
      msg_ok "$1"
      ok=$((ok + 1))
    else
      msg_err "$1"
      fail=$((fail + 1))
    fi
  }
  check_one "PHP" "php -v"
  check_one "MariaDB" "systemctl is-active mariadb"
  check_one "Nginx" "systemctl is-active nginx"
  check_one "$(hkz_t info_queue)" "systemctl is-active pteroq"
  check_one "$(hkz_t info_panel)" "[ -f $PANEL_DIR/artisan ]"
  check_one "$(hkz_t info_redis_off)" "! systemctl is-active redis-server 2>/dev/null && ! systemctl is-active redis 2>/dev/null"
  if [ -f "$PANEL_DIR/.env" ]; then
    grep -q 'QUEUE_CONNECTION=database' "$PANEL_DIR/.env" && msg_ok "$(hkz_t info_queue_mysql)" || msg_warn "$(hkz_t info_queue_warn)"
    grep -q 'CACHE_DRIVER=database' "$PANEL_DIR/.env" && msg_ok "$(hkz_t info_cache_mysql)" || msg_warn "$(hkz_t info_cache_warn)"
  fi
  if [ -d "$PANEL_DIR" ]; then
    panel_ver=$(cd "$PANEL_DIR" && php artisan p:info 2>/dev/null | grep -i version | head -1 || hkz_t ver_unknown)
    msg_info "$(hkz_t info_panel_ver): $panel_ver"
    msg_info "$(hkz_t info_github_ver): $(get_latest_release pterodactyl/panel 2>/dev/null || echo ?)"
  fi
  [ -f "$PANEL_DIR/blueprint.sh" ] && msg_warn "$(hkz_t info_blueprint)"
  msg_info "$(hkz_t theme_current): $(hkz_theme_current_label)"
  if hkz_panel_read_setting 'app:name' >/dev/null 2>&1; then
    local cname
    cname=$(hkz_panel_read_setting 'app:name' 2>/dev/null || true)
    [ -n "$cname" ] && msg_info "Company Name (DB): $cname"
  fi
  [ -f "$PANEL_DIR/public/assets/hkz/client.css" ] && msg_ok "HKZ Aurora CSS" || true
  msg_ok "$(hkz_t info_installer) v$(read_local_version) (rev $(tr -d '[:space:]' <"${HKZ_INSTALL_DIR}/INSTALLER_REV" 2>/dev/null || echo ?))"
  df -h / /var 2>/dev/null | tail -n +2 | while read -r line; do msg_info "$(hkz_t info_disk): $line"; done
  msg_info "$(hkz_t info_summary)=$ok $(hkz_t info_errors)=$fail"
  [ "$fail" -eq 0 ]
}
