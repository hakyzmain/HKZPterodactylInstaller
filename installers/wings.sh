#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

hkz_wings_load_env

[ -z "${OS:-}" ] && detect_os
[ -z "${OS:-}" ] && { msg_err "$(hkz_t wings_os_undef)"; exit 1; }
hkz_export_wings_env

CONFIGS_DIR="$(dirname "${BASH_SOURCE[0]}")/../configs"
export CONFIGS_DIR
INSTALL_MARIADB="${INSTALL_MARIADB:-false}"
CONFIGURE_FIREWALL="${WINGS_CONFIGURE_FIREWALL:-false}"
CONFIGURE_LETSENCRYPT="${WINGS_CONFIGURE_SSL:-false}"
FQDN="${WINGS_FQDN:-}"
EMAIL="${WINGS_EMAIL:-}"
MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pterodactyluser}"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"
MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"

wings_deps() {
  msg_step "$(hkz_t wings_deps)"
  [ "$CONFIGURE_FIREWALL" = true ] && install_firewall
  case "$OS" in
    ubuntu|debian)
      hkz_docker_apt_repo
      ;;
    rocky|almalinux)
      install_packages dnf-plugins-core
      dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
      install_packages device-mapper-persistent-data lvm2
      ;;
  esac
  update_repos
  install_packages docker-ce docker-ce-cli containerd.io
  if [ "$CONFIGURE_LETSENCRYPT" = true ]; then
    install_packages nginx
    install_packages certbot python3-certbot-nginx
  fi
  [ "$INSTALL_MARIADB" = true ] && install_packages mariadb-server
  systemctl enable --now docker
  [ "$INSTALL_MARIADB" = true ] && systemctl enable --now mariadb
  if [ "$CONFIGURE_FIREWALL" = true ]; then
    firewall_allow_ports "22 8080 2022"
    [ "$CONFIGURE_LETSENCRYPT" = true ] && firewall_allow_ports "80 443"
  fi
  msg_ok "$(hkz_t wings_docker_ok)"
}

wings_download() {
  msg_step "wings"
  hkz_ensure_wings_etc
  hkz_wings_ensure_binary
  hkz_wings_link_binary
  cp "$CONFIGS_DIR/wings.service" /etc/systemd/system/wings.service
  systemctl daemon-reload
  systemctl enable wings
  msg_ok "$(hkz_t wings_dl_ok)"
}

wings_mysql() {
  [ "$WINGS_DBHOST" != true ] && return 0
  msg_step "$(hkz_t wings_mysql)"
  create_db_user "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_PASSWORD" "$MYSQL_DBHOST_HOST"
  grant_db_all "*" "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_HOST"
  msg_ok "$(hkz_t wings_mysql_ok)"
}

wings_autodeploy() {
  [ -z "$WINGS_DEPLOY_CMD" ] && return 0
  msg_step "auto-deploy"
  hkz_wings_run_deploy "$WINGS_DEPLOY_CMD" && msg_ok "$(hkz_t wings_deploy_ok)" || msg_warn "$(hkz_t wings_deploy_warn)"
}

wings_setup_ssl() {
  local domain
  [ "$CONFIGURE_LETSENCRYPT" != true ] && return 0
  domain=$(hkz_wings_ssl_domain 2>/dev/null) || domain="$FQDN"
  [ -z "$domain" ] && return 0
  hkz_fqdn_is_ip "$domain" && return 0
  hkz_wings_setup_node_ssl "$domain" "$EMAIL" || {
    msg_warn "$(hkz_t wings_cert_warn)"
    hkz_wings_fix_config_ssl
  }
}

wings_main() {
  detect_os
  wings_deps
  wings_download
  wings_mysql
  hkz_mark_wings
  wings_autodeploy
  wings_setup_ssl
  hkz_wings_start || msg_warn "$(hkz_t wings_heal_start_fail)"
  msg_ok "$(hkz_t wings_done)"
}

wings_main
