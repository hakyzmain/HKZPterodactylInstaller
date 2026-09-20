#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/verify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-customize.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-heal.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-admin.sh"

[ -z "${OS:-}" ] && detect_os
[ -z "${OS:-}" ] && { msg_err "$(hkz_t panel_os_undef)"; exit 1; }
CONFIGS_DIR="$(dirname "${BASH_SOURCE[0]}")/../configs"
export CONFIGS_DIR

install_composer() {
  msg_step "Composer"
  if ! command -v composer &>/dev/null; then
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  fi
  msg_ok "$(hkz_t panel_composer_ok)"
}

hkz_php_sury_repo() {
  install_packages dirmngr ca-certificates apt-transport-https lsb-release gnupg curl
  curl -fsSL -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
  rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list 2>/dev/null || true
}

ubuntu_php_repo() {
  hkz_apt_prefer_ipv4
  hkz_php_sury_repo
}

debian_php_repo() {
  hkz_apt_prefer_ipv4
  hkz_php_sury_repo
}

dep_install() {
  msg_step "$(hkz_t panel_sys_packages)"
  update_repos
  case "$OS" in
    ubuntu)
      ubuntu_php_repo
      update_repos
      install_packages php8.3 php8.3-cli php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip mariadb-server mariadb-client nginx zip unzip tar git cron
      [ "$CONFIGURE_LETSENCRYPT" = true ] && install_packages certbot python3-certbot-nginx
      WEB_USER=www-data WEB_GROUP=www-data PHP_SOCKET=/run/php/php8.3-fpm.sock NGINX_AVAIL=/etc/nginx/sites-available NGINX_ENABL=/etc/nginx/sites-enabled
      ;;
    debian)
      debian_php_repo
      update_repos
      install_packages php8.3 php8.3-cli php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip mariadb-server mariadb-client nginx zip unzip tar git cron
      [ "$CONFIGURE_LETSENCRYPT" = true ] && install_packages certbot python3-certbot-nginx
      WEB_USER=www-data WEB_GROUP=www-data PHP_SOCKET=/run/php/php8.3-fpm.sock NGINX_AVAIL=/etc/nginx/sites-available NGINX_ENABL=/etc/nginx/sites-enabled
      ;;
    rocky|almalinux)
      install_packages epel-release "https://rpms.remirepo.net/enterprise/remi-release-${OS_VER_MAJOR}.rpm"
      dnf module enable -y php:remi-8.3
      install_packages php php-cli php-common php-gd php-mysqlnd php-mbstring php-bcmath php-xml php-fpm php-curl php-zip mariadb-server nginx zip unzip tar git cronie
      [ "$CONFIGURE_LETSENCRYPT" = true ] && install_packages certbot python3-certbot-nginx
      WEB_USER=nginx WEB_GROUP=nginx PHP_SOCKET=/var/run/php-fpm/pterodactyl.sock NGINX_AVAIL=/etc/nginx/conf.d NGINX_ENABL=/etc/nginx/conf.d
      setsebool -P httpd_can_network_connect 1 2>/dev/null || true
      ;;
  esac
  [ -z "$OS" ] && { msg_err "$(hkz_t panel_os_restart)"; exit 1; }
  systemctl enable --now mariadb nginx
  export WEB_USER WEB_GROUP PHP_SOCKET NGINX_AVAIL NGINX_ENABL
  hkz_export_panel_env
  hkz_ensure_php_fpm || exit 1
  msg_ok "$(hkz_t panel_packages_ok)"
}

configure_firewall() {
  [ "$CONFIGURE_FIREWALL" != true ] && return 0
  msg_step "Firewall"
  install_firewall
  firewall_allow_ports "22 80 443"
  msg_ok "$(hkz_t panel_fw_ok)"
}

download_panel() {
  hkz_resolve_panel_dir 2>/dev/null || true
  if hkz_panel_core_ok 2>/dev/null; then
    msg_info "$(hkz_t panel_use_existing) ${PANEL_DIR}"
    hkz_verify_panel_tree || return 1
    return 0
  fi
  msg_step "$(hkz_t panel_dl)"
  local tgz="/tmp/pterodactyl-panel.tar.gz" env_bak=""
  local urls=() url ok=0 tag
  urls+=("${PANEL_DL_URL}")
  urls+=("https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz")
  tag=$(get_latest_release pterodactyl/panel 2>/dev/null || true)
  tag=${tag#v}
  [ -n "$tag" ] && urls+=("https://github.com/pterodactyl/panel/releases/download/v${tag}/panel.tar.gz")
  urls+=("https://mirror.ghproxy.com/https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz")
  mkdir -p "$PANEL_DIR"
  [ -f "${PANEL_DIR}/.env" ] && { env_bak=$(mktemp); cp -a "${PANEL_DIR}/.env" "$env_bak"; }
  for url in "${urls[@]}"; do
    [ -n "$url" ] || continue
    rm -f "$tgz"
    hkz_download "$url" "$tgz" "panel.tar.gz" || continue
    hkz_panel_archive_ok "$tgz" || {
      msg_warn "$(hkz_t panel_archive_bad)"
      rm -f "$tgz"
      continue
    }
    ok=1
    break
  done
  [ "$ok" = 1 ] || { [ -n "$env_bak" ] && rm -f "$env_bak"; return 1; }
  mkdir -p "$HKZ_STAMP_DIR"
  cp -f "$tgz" "${HKZ_STAMP_DIR}/panel-stock-cache.tar.gz"
  msg_info "$(hkz_t panel_unpack) $PANEL_DIR"
  hkz_panel_extract_tgz "$tgz" "$PANEL_DIR" || {
    rm -f "$tgz" "$env_bak"
    msg_err "$(hkz_t panel_archive_bad)"
    return 1
  }
  rm -f "$tgz"
  if [ -n "$env_bak" ]; then
    mv -f "$env_bak" "${PANEL_DIR}/.env"
  else
    cp -n "${PANEL_DIR}/.env.example" "${PANEL_DIR}/.env" 2>/dev/null || true
  fi
  chmod -R 755 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
  hkz_verify_panel_tree || return 1
  msg_ok "$(hkz_t panel_ok_ver) $(get_latest_release pterodactyl/panel)"
}

composer_install() {
  msg_step "$(hkz_t panel_php_deps)"
  cd "$PANEL_DIR"
  [ "$OS" = rocky ] || [ "$OS" = almalinux ] && export PATH=/usr/local/bin:$PATH
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  msg_ok "$(hkz_t panel_php_ok)"
}

setup_database() {
  [ -z "$MYSQL_PASSWORD" ] && msg_err "$(hkz_t panel_mysql_pass)" && exit 1
  msg_step "MySQL"
  MYSQL_USER="${MYSQL_USER:-pterodactyl}"
  MYSQL_DB="${MYSQL_DB:-panel}"
  export MYSQL_USER MYSQL_DB MYSQL_PASSWORD
  if [ "${HKZ_FRESH_PANEL_INSTALL:-0}" = 1 ]; then
    hkz_panel_prepare_fresh_database || exit 1
  fi
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD" || exit 1
  create_db "$MYSQL_DB" "$MYSQL_USER" || exit 1
  sleep 2
  if ! hkz_mysql_test_connection; then
    msg_warn "$(hkz_t panel_db_conn_fail)"
    create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD" || exit 1
    create_db "$MYSQL_DB" "$MYSQL_USER" || exit 1
    sleep 1
    hkz_mysql_test_connection || {
      msg_err "$(hkz_t panel_db_conn_fail)"
      exit 1
    }
  fi
  msg_ok "$(hkz_t panel_mysql_ok) (${MYSQL_DBHOST_HOST:-localhost})"
}

configure_panel_existing() {
  msg_step "$(hkz_t panel_configure)"
  cd "$PANEL_DIR"
  hkz_panel_load_db_from_env 2>/dev/null || true
  [ -z "$MYSQL_PASSWORD" ] && msg_err "$(hkz_t panel_mysql_pass)" && exit 1
  [ ! -f .env ] && msg_err "$(hkz_t panel_no_env)" && exit 1
  hkz_panel_ensure_db_env "$MYSQL_USER" "$MYSQL_PASSWORD" "$MYSQL_DB" || exit 1
  hkz_mysql_test_connection || {
    msg_err "$(hkz_t panel_db_conn_fail)"
    exit 1
  }
  msg_info "$(hkz_t panel_external_configure)"
  if declare -F hkz_panel_ensure_app_key >/dev/null 2>&1; then
    hkz_panel_ensure_app_key || {
      msg_err "$(hkz_t panel_heal_key_fail)"
      exit 1
    }
  else
    php artisan key:generate --force --no-interaction || true
  fi
  php artisan migrate --force --no-interaction
  hkz_panel_ensure_settings_ui || true
  hkz_panel_ensure_service_author || true
  hkz_panel_apply_database_drivers || {
    msg_err "$(hkz_t panel_db_drv_fail)"
    exit 1
  }
  hkz_panel_apply_customization || msg_warn "$(hkz_t panel_locale_warn) ${LOG_PATH}"
  hkz_panel_set_users_language
  chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"
  msg_ok "$(hkz_t panel_configured)"
}

configure_panel() {
  cd "$PANEL_DIR"
  if hkz_panel_external_install; then
    configure_panel_existing
    return 0
  fi
  msg_step "$(hkz_t panel_configure)"
  [ -z "$MYSQL_PASSWORD" ] && msg_err "$(hkz_t panel_mysql_pass)" && exit 1
  local app_url="http://${FQDN}"
  [ "$ASSUME_SSL" = true ] || [ "$CONFIGURE_LETSENCRYPT" = true ] && app_url="https://${FQDN}"

  if [ ! -f .env ]; then
    cp -f .env.example .env
  fi
  php artisan key:generate --force

  php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="$timezone" \
    --cache=file \
    --session=file \
    --queue=sync \
    --settings-ui=true \
    --telemetry=false \
    --no-interaction

  hkz_panel_ensure_settings_ui || true
  hkz_panel_ensure_service_author || true

  hkz_mysql_test_connection || {
    create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD" || exit 1
    create_db "$MYSQL_DB" "$MYSQL_USER" || exit 1
    hkz_mysql_test_connection || {
      msg_err "$(hkz_t panel_db_conn_fail)"
      exit 1
    }
  }

  php artisan p:environment:database \
    --host="${MYSQL_DBHOST_HOST:-localhost}" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD" \
    --no-interaction

  hkz_panel_ensure_db_env "$MYSQL_USER" "$MYSQL_PASSWORD" "$MYSQL_DB" || {
    msg_err "$(hkz_t panel_db_conn_fail)"
    exit 1
  }

  hkz_panel_mail_log
  msg_info "$(hkz_t panel_mail_log)"

  php artisan migrate --seed --force --no-interaction

  hkz_panel_mail_log

  hkz_panel_ensure_admin_user || exit 1

  grep -q '^PTERODACTYL_TELEMETRY_ENABLED=' .env 2>/dev/null && \
    sed -i 's/^PTERODACTYL_TELEMETRY_ENABLED=.*/PTERODACTYL_TELEMETRY_ENABLED=false/' .env || \
    echo 'PTERODACTYL_TELEMETRY_ENABLED=false' >>.env

  hkz_panel_apply_database_drivers || {
    msg_err "$(hkz_t panel_db_drv_fail)"
    exit 1
  }
  hkz_panel_apply_customization || msg_warn "$(hkz_t panel_locale_warn) ${LOG_PATH}"
  hkz_panel_set_users_language
  chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"
  msg_ok "$(hkz_t panel_configured)"
}

setup_cron() {
  msg_step "Cron"
  (crontab -u "$WEB_USER" -l 2>/dev/null | grep -v 'schedule:run'; echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1") | crontab -u "$WEB_USER" -
  msg_ok "$(hkz_t panel_cron_ok)"
}

setup_queue_worker() {
  msg_step "$(hkz_t panel_pteroq)"
  sed -e "s|@WEBUSER@|${WEB_USER}|g" -e "s|@PANEL_DIR@|${PANEL_DIR}|g" "$CONFIGS_DIR/pteroq.service" > /etc/systemd/system/pteroq.service
  systemctl daemon-reload
  systemctl enable --now pteroq
  msg_ok "$(hkz_t panel_pteroq_ok)"
}

configure_nginx() {
  msg_step "Nginx"
  local tpl="nginx.conf"
  hkz_resolve_php_fpm_env || exit 1
  hkz_ensure_php_fpm || exit 1
  if [ "$ASSUME_SSL" = true ] && [ "$CONFIGURE_LETSENCRYPT" != true ]; then
    if [ -f "/etc/letsencrypt/live/${FQDN}/fullchain.pem" ]; then
      tpl="nginx_ssl.conf"
    else
      msg_warn "$(hkz_t panel_ssl_assume_missing)"
    fi
  fi
  rm -f "${NGINX_ENABL}/default" 2>/dev/null || true
  cp "$CONFIGS_DIR/$tpl" "${NGINX_AVAIL}/pterodactyl.conf"
  sed -i "s|@FQDN@|${FQDN}|g" "${NGINX_AVAIL}/pterodactyl.conf"
  sed -i "s|@PHP_SOCKET@|${PHP_SOCKET}|g" "${NGINX_AVAIL}/pterodactyl.conf"
  sed -i "s|@PANEL_DIR@|${PANEL_DIR}|g" "${NGINX_AVAIL}/pterodactyl.conf"
  if [ "$OS" = ubuntu ] || [ "$OS" = debian ]; then
    ln -sf "${NGINX_AVAIL}/pterodactyl.conf" "${NGINX_ENABL}/pterodactyl.conf"
  fi
  nginx -t
  systemctl enable nginx 2>/dev/null || true
  systemctl restart nginx
  msg_ok "$(hkz_t panel_nginx_ok)"
}

setup_letsencrypt() {
  [ "$CONFIGURE_LETSENCRYPT" != true ] && return 0
  msg_step "SSL"
  if certbot --nginx --redirect --no-eff-email --email "$email" -d "$FQDN"; then
    ASSUME_SSL=true
    export ASSUME_SSL
    hkz_panel_ensure_app_url 2>/dev/null || true
    hkz_panel_artisan_clear_caches 2>/dev/null || true
    msg_ok "$(hkz_t panel_ssl_ok)"
  else
    msg_warn "$(hkz_t panel_ssl_fail)"
  fi
}

panel_install_main() {
  hkz_resolve_panel_dir 2>/dev/null || true
  local existing=0
  [ -f "${PANEL_DIR}/artisan" ] && existing=1
  export HKZ_FRESH_PANEL_INSTALL=$((1 - existing))
  if [ "$existing" = 0 ]; then
    dep_install
  else
    hkz_set_web_user || exit 1
    hkz_resolve_php_fpm_env || exit 1
    hkz_ensure_php_fpm || exit 1
  fi
  configure_firewall
  install_composer
  download_panel
  composer_install
  setup_database
  configure_panel
  setup_cron
  [ ! -f /etc/systemd/system/pteroq.service ] && setup_queue_worker
  configure_nginx
  setup_letsencrypt
  hkz_panel_finalize
  hkz_panel_save_install_secrets
  hkz_mark_panel
}

panel_install_main
