#!/bin/bash

hkz_b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

hkz_panel_admin_php() {
  local action="$1" script tpl
  for tpl in \
    "${CONFIGS_DIR:-}/panel-admin.php" \
    "$(dirname "${BASH_SOURCE[0]}")/../configs/panel-admin.php"; do
    [ -f "$tpl" ] && script="$tpl" && break
  done
  [ -n "$script" ] || return 1
  [ -n "${user_email:-}" ] && [ -n "${user_password:-}" ] || return 1
  PANEL_DIR="${PANEL_DIR}" \
    HKZ_ADMIN_ACTION="$action" \
    HKZ_USER_EMAIL="${user_email}" \
    HKZ_USER_USERNAME="${user_username:-admin}" \
    HKZ_USER_FIRST="${user_firstname:-Admin}" \
    HKZ_USER_LAST="${user_lastname:-User}" \
    HKZ_USER_PASSWORD_B64="$(hkz_b64 "$user_password")" \
    php "$script"
}

hkz_panel_verify_admin_password() {
  hkz_panel_admin_php verify >>"$LOG_PATH" 2>&1
}

hkz_panel_ensure_admin_user() {
  [ -f "${PANEL_DIR}/artisan" ] || return 1
  [ -n "${user_email:-}" ] || return 1
  [ -n "${user_password:-}" ] || return 1
  msg_step "$(hkz_t panel_admin_setup)"
  if hkz_panel_admin_exists; then
    msg_info "$(hkz_t panel_admin_pass_reset)"
  fi
  hkz_panel_admin_php ensure >>"$LOG_PATH" 2>&1 || {
    msg_err "$(hkz_t panel_admin_fail)"
    return 1
  }
  hkz_panel_verify_admin_password || {
    msg_err "$(hkz_t panel_admin_verify_fail)"
    return 1
  }
  ADMIN_SKIPPED=0
  export ADMIN_SKIPPED
  msg_ok "$(hkz_t panel_admin_ok)"
  return 0
}
