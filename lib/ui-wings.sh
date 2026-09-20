#!/bin/bash

export WINGS_FQDN="${WINGS_FQDN:-}"
export WINGS_EMAIL="${WINGS_EMAIL:-}"
export WINGS_CONFIGURE_SSL="${WINGS_CONFIGURE_SSL:-false}"
export WINGS_CONFIGURE_FIREWALL="${WINGS_CONFIGURE_FIREWALL:-false}"
export WINGS_DBHOST="${WINGS_DBHOST:-false}"
export WINGS_DEPLOY_CMD="${WINGS_DEPLOY_CMD:-}"

run_wings_ui() {
  hkz_panel_load_install_secrets 2>/dev/null || true
  draw_logo
  print_rule
  if hkz_has_wings; then
    msg_warn "$(hkz_t wings_already)"
    echo -en "  $(hkz_t wings_continue) "
    read -r c
    [[ ! "$c" =~ ^[Yy] ]] && return 1
  fi
  check_virt
  echo -en "  $(hkz_t wings_fw) "
  read -r fw
  [[ "$fw" =~ ^[Yy] ]] && WINGS_CONFIGURE_FIREWALL=true
  echo -en "  $(hkz_t wings_mysql_q) "
  read -r db
  [[ "$db" =~ ^[Yy] ]] && WINGS_DBHOST=true
  if [ "$WINGS_DBHOST" = true ]; then
    required_input MYSQL_DBHOST_USER "$(hkz_t ui_mysql_user)" "" "pterodactyluser"
    MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-$(openssl rand -hex 16 2>/dev/null || true)}"
    password_input MYSQL_DBHOST_PASSWORD "$(hkz_t ui_mysql_pass)" "$(hkz_t ui_pass_required)" "$MYSQL_DBHOST_PASSWORD" 1
  fi
  echo -en "  $(hkz_t wings_domain_q) "
  read -r WINGS_FQDN
  if [ -z "$WINGS_FQDN" ]; then
    WINGS_FQDN=$(get_machine_ip)
    WINGS_CONFIGURE_SSL=false
    msg_info "$(hkz_t wings_http_node)${WINGS_FQDN}"
  elif hkz_fqdn_is_ip "$WINGS_FQDN"; then
    WINGS_CONFIGURE_SSL=false
    msg_info "$(hkz_t wings_ssl_ip_off)${WINGS_FQDN}"
  else
    WINGS_CONFIGURE_SSL=true
    [ -z "$WINGS_EMAIL" ] && [ -n "${email:-}" ] && WINGS_EMAIL="$email"
    [ -z "$WINGS_EMAIL" ] && email_input WINGS_EMAIL "$(hkz_t ui_ssl_email)" "$(hkz_t ui_bad_email)"
  fi
  echo ""
  msg_info "$(hkz_t wings_deploy_hint)"
  echo -en "  $(hkz_t wings_deploy_q) "
  read -r WINGS_DEPLOY_CMD
  echo -en "  $(hkz_t wings_start_q) "
  read -r go
  [[ "$go" =~ ^[Nn] ]] && return 1
  export WINGS_FQDN WINGS_EMAIL WINGS_CONFIGURE_SSL WINGS_CONFIGURE_FIREWALL WINGS_DBHOST WINGS_DEPLOY_CMD
  export MYSQL_DBHOST_USER MYSQL_DBHOST_PASSWORD MYSQL_DBHOST_HOST
  return 0
}
