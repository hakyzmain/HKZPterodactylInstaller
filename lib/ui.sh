#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/panel-customize.sh"

export FQDN="${FQDN:-}"
export MYSQL_DB="${MYSQL_DB:-panel}"
export MYSQL_USER="${MYSQL_USER:-pterodactyl}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
export timezone="${timezone:-}"
export email="${email:-}"
export user_email="${user_email:-}"
export user_username="${user_username:-admin}"
export user_firstname="${user_firstname:-Admin}"
export user_lastname="${user_lastname:-User}"
export user_password="${user_password:-}"
export ASSUME_SSL="${ASSUME_SSL:-false}"
export CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
export CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"
export INSTALL_HKZ_THEME="${INSTALL_HKZ_THEME:-false}"
export PANEL_LOCALE="${PANEL_LOCALE:-ru}"
export NONINTERACTIVE="${NONINTERACTIVE:-false}"

run_ui() {
  load_config_file "${CONFIG_FILE:-}"
  hkz_detect_timezone
  if [ "$NONINTERACTIVE" = true ] || [ -n "$FQDN" ]; then
    validate_noninteractive
    return 0
  fi
  draw_logo
  print_rule
  if hkz_panel_core_ok 2>/dev/null; then
    msg_err "$(hkz_t ui_panel_exists) $PANEL_DIR"
    msg_info "$(hkz_t ui_theme8_remove3)"
    exit 1
  fi
  while [[ "$MYSQL_DB" == *"-"* ]]; do
    required_input MYSQL_DB "$(hkz_t ui_db_name)" "$(hkz_t ui_no_dash)" "panel"
    [[ "$MYSQL_DB" == *"-"* ]] && msg_err "$(hkz_t ui_no_dash)"
  done
  while [[ "$MYSQL_USER" == *"-"* ]]; do
    required_input MYSQL_USER "$(hkz_t ui_mysql_user)" "$(hkz_t ui_no_dash)" "pterodactyl"
    [[ "$MYSQL_USER" == *"-"* ]] && msg_err "$(hkz_t ui_no_dash)"
  done
  [ -z "$MYSQL_PASSWORD" ] && MYSQL_PASSWORD=$(gen_passwd 32)
  password_input MYSQL_PASSWORD "$(hkz_t ui_mysql_pass)" "$(hkz_t ui_pass_required)" "$MYSQL_PASSWORD" 1
  email_input email "$(hkz_t ui_ssl_email)" "$(hkz_t ui_bad_email)"
  email_input user_email "$(hkz_t ui_admin_email)" "$(hkz_t ui_bad_email)"
  password_input user_password "$(hkz_t ui_admin_pass)" "$(hkz_t ui_pass_required)"
  required_input user_username "$(hkz_t ui_username)" "" "$user_username"
  required_input user_firstname "$(hkz_t ui_firstname)" "" "$user_firstname"
  required_input user_lastname "$(hkz_t ui_lastname)" "" "$user_lastname"
  print_rule
  echo "  $(hkz_t ui_panel_lang_title)"
  echo "  $(hkz_t ui_panel_lang1)"
  echo "  $(hkz_t ui_panel_lang2)"
  echo -en "  $(hkz_t ui_panel_lang_choice): "
  read -r lang_choice
  case "$lang_choice" in
    1|en|EN|english) PANEL_LOCALE=en ;;
    2|ru|RU|рус|"") PANEL_LOCALE=ru ;;
    *) msg_err "$(hkz_t ui_panel_lang_bad)"; exit 1 ;;
  esac
  export PANEL_LOCALE
  msg_info "$(hkz_t ui_panel_lang_set): $([ "$PANEL_LOCALE" = ru ] && hkz_t lang_ru || hkz_t lang_en)"
  print_rule
  echo -en "  $(hkz_t ui_fqdn): "
  read -r FQDN
  hkz_resolve_fqdn
  echo -en "  $(hkz_t ui_firewall) "
  read -r fw
  [[ "$fw" =~ ^[Yy] ]] && CONFIGURE_FIREWALL=true && export CONFIGURE_FIREWALL
  if ! hkz_fqdn_is_ip "$FQDN" && [[ $(invalid_ip "$FQDN") == 1 ]]; then
    echo -en "  $(hkz_t ui_ssl_le) "
    read -r ssl
    [[ "$ssl" =~ ^[Yy] ]] && CONFIGURE_LETSENCRYPT=true
    if [ "$CONFIGURE_LETSENCRYPT" != true ]; then
      echo -en "  $(hkz_t ui_ssl_nginx) "
      read -r asl
      [[ "$asl" =~ ^[Yy] ]] && ASSUME_SSL=true
    fi
  fi
  msg_info "$(hkz_t ui_theme_auto)"
  print_rule
  if hkz_fqdn_is_ip "$FQDN"; then
    echo "  $(hkz_t ui_addr): http://${FQDN}"
  else
    echo "  $(hkz_t ui_domain): $FQDN"
  fi
  echo "  $(hkz_t ui_admin_line): $user_username / $user_email"
  print_rule
  echo -en "  $(hkz_t ui_start) "
  read -r go
  [[ "$go" =~ ^[Nn] ]] && exit 1
  hkz_export_panel_env
}

validate_noninteractive() {
  hkz_detect_timezone
  PANEL_LOCALE=$(hkz_panel_normalize_locale "${PANEL_LOCALE:-ru}" 2>/dev/null || echo "${PANEL_LOCALE:-ru}")
  export PANEL_LOCALE
  local missing=()
  for v in email user_email user_password MYSQL_PASSWORD; do
    [ -z "${!v}" ] && missing+=("$v")
  done
  [ ${#missing[@]} -gt 0 ] && msg_err "$(hkz_t ui_missing): ${missing[*]}" && exit 1
  [ -z "$MYSQL_PASSWORD" ] && MYSQL_PASSWORD=$(gen_passwd 32)
  hkz_resolve_fqdn
  hkz_export_panel_env
}
