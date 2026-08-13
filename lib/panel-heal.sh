#!/bin/bash

if ! declare -F hkz_panel_ensure_admin_user >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/panel-admin.sh"
fi

hkz_panel_ensure_app_key() {
  local key env="${PANEL_DIR}/.env" new_key
  [ -f "$env" ] || return 1
  rm -f "${PANEL_DIR}/bootstrap/cache/config.php" \
    "${PANEL_DIR}/bootstrap/cache/packages.php" \
    "${PANEL_DIR}/bootstrap/cache/services.php" 2>/dev/null || true
  key=$(hkz_panel_env_val APP_KEY 2>/dev/null || echo "")
  if [ -n "$key" ] && [ "$key" != "null" ] && [ "$key" != "SomeRandomString" ] && [ "$key" != '""' ] && [ "$key" != "''" ]; then
    key=${key#base64:}
    [ "${#key}" -ge 16 ] && return 0
  fi
  sed -i '/^APP_KEY=/d' "$env"
  if (cd "$PANEL_DIR" && php artisan key:generate --force --no-interaction >>"$LOG_PATH" 2>&1); then
    key=$(hkz_panel_env_val APP_KEY 2>/dev/null || echo "")
    key=${key#base64:}
    [ "${#key}" -ge 16 ] && return 0
  fi
  new_key=$(php -r 'echo "base64:".base64_encode(random_bytes(32));' 2>/dev/null) || return 1
  [ -n "$new_key" ] || return 1
  sed -i '/^APP_KEY=/d' "$env"
  printf '%s\n' "APP_KEY=${new_key}" >>"$env"
  rm -f "${PANEL_DIR}/bootstrap/cache/config.php" 2>/dev/null || true
  key=$(hkz_panel_env_val APP_KEY 2>/dev/null || echo "")
  key=${key#base64:}
  [ "${#key}" -ge 16 ]
}

hkz_panel_ensure_app_url() {
  local env="${PANEL_DIR}/.env" url host
  [ -f "$env" ] || return 1
  host="${FQDN:-$(hkz_panel_env_val APP_URL 2>/dev/null | sed -E 's#https?://##; s#/.*##')}"
  [ -n "$host" ] || host=localhost
  url="http://${host}"
  if [ "${ASSUME_SSL:-false}" = true ] || [ "${CONFIGURE_LETSENCRYPT:-false}" = true ] \
    || [ -f "/etc/letsencrypt/live/${host}/fullchain.pem" ]; then
    url="https://${host}"
  fi
  hkz_panel_env_set "$env" APP_URL "$url"
  return 0
}

hkz_panel_ensure_storage_dirs() {
  local base="${PANEL_DIR}/storage"
  mkdir -p \
    "${base}/app/public" \
    "${base}/framework/cache/data" \
    "${base}/framework/sessions" \
    "${base}/framework/views" \
    "${base}/logs" \
    "${PANEL_DIR}/bootstrap/cache"
  return 0
}

hkz_panel_fix_permissions() {
  hkz_set_web_user || return 1
  hkz_panel_ensure_storage_dirs
  chown -R "${WEB_USER}:${WEB_GROUP}" "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
  chmod -R ug+rwx "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
  find "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" -type d -exec chmod ug+rwx {} + 2>/dev/null || true
  find "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" -type f -exec chmod ug+rw {} + 2>/dev/null || true
  case "$OS" in
    rocky|almalinux)
      command -v restorecon >/dev/null 2>&1 && \
        restorecon -Rv "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" >>"$LOG_PATH" 2>&1 || true
      setsebool -P httpd_can_network_connect 1 2>/dev/null || true
      ;;
  esac
  return 0
}

hkz_panel_artisan_clear_caches() {
  [ -f "${PANEL_DIR}/artisan" ] || return 1
  (
    cd "$PANEL_DIR"
    php artisan config:clear --no-interaction >>"$LOG_PATH" 2>&1 || true
    php artisan cache:clear --no-interaction >>"$LOG_PATH" 2>&1 || true
    php artisan route:clear --no-interaction >>"$LOG_PATH" 2>&1 || true
    php artisan view:clear --no-interaction >>"$LOG_PATH" 2>&1 || true
    rm -f bootstrap/cache/config.php bootstrap/cache/routes-v7.php bootstrap/cache/services.php 2>/dev/null || true
  )
  return 0
}

hkz_panel_ensure_db_connection() {
  hkz_panel_load_install_secrets 2>/dev/null || true
  hkz_panel_load_db_from_env 2>/dev/null || true
  [ -n "${MYSQL_PASSWORD:-}" ] || return 1
  MYSQL_USER="${MYSQL_USER:-pterodactyl}"
  MYSQL_DB="${MYSQL_DB:-panel}"
  hkz_ensure_mariadb_running
  if hkz_mysql_test_connection; then
    hkz_panel_ensure_db_env "$MYSQL_USER" "$MYSQL_PASSWORD" "$MYSQL_DB" 2>/dev/null || true
    return 0
  fi
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD" || return 1
  create_db "$MYSQL_DB" "$MYSQL_USER" || return 1
  hkz_mysql_test_connection || return 1
  hkz_panel_ensure_db_env "$MYSQL_USER" "$MYSQL_PASSWORD" "$MYSQL_DB" || return 1
  return 0
}

hkz_panel_ensure_drivers() {
  local env="${PANEL_DIR}/.env"
  [ -f "$env" ] || return 1
  if hkz_panel_apply_database_drivers >>"$LOG_PATH" 2>&1; then
    return 0
  fi
  msg_warn "$(hkz_t panel_db_drv_fallback)"
  sed -i 's/^CACHE_DRIVER=.*/CACHE_DRIVER=file/' "$env"
  sed -i 's/^SESSION_DRIVER=.*/SESSION_DRIVER=file/' "$env"
  sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=sync/' "$env"
  hkz_panel_artisan_clear_caches
  return 0
}

hkz_nginx_sync_php_socket() {
  local conf
  hkz_resolve_php_fpm_env 2>/dev/null || return 0
  hkz_detect_php_socket 2>/dev/null || return 0
  for conf in \
    "${NGINX_AVAIL:-/etc/nginx/sites-available}/pterodactyl.conf" \
    "${NGINX_ENABL:-/etc/nginx/sites-enabled}/pterodactyl.conf" \
    /etc/nginx/conf.d/pterodactyl.conf; do
    [ -f "$conf" ] || continue
    grep -q 'fastcgi_pass unix:' "$conf" || continue
    sed -i "s|fastcgi_pass unix:[^;]*|fastcgi_pass unix:${PHP_SOCKET}|" "$conf"
  done
  nginx -t >>"$LOG_PATH" 2>&1 && systemctl restart nginx >>"$LOG_PATH" 2>&1
  return 0
}

hkz_panel_artisan_boot_test() {
  [ -f "${PANEL_DIR}/artisan" ] || return 1
  (cd "$PANEL_DIR" && php artisan about --no-interaction >>"$LOG_PATH" 2>&1)
}

hkz_panel_http_probe() {
  local host code url scheme
  host="${FQDN:-localhost}"
  host=${host#http://}
  host=${host#https://}
  host=${host%%/*}
  for scheme in http https; do
    [ "$scheme" = https ] && [ ! -f "/etc/letsencrypt/live/${host}/fullchain.pem" ] \
      && [ "${ASSUME_SSL:-false}" != true ] && continue
    url="${scheme}://127.0.0.1/"
    code=$(curl -sk -o /dev/null -w '%{http_code}' -H "Host: ${host}" "$url" 2>/dev/null) || code=0
    case "$code" in
      200|301|302|303|307|308) return 0 ;;
    esac
  done
  return 1
}

hkz_panel_dump_diagnostics() {
  local log="${PANEL_DIR}/storage/logs/laravel.log"
  msg_warn "$(hkz_t panel_heal_diag)"
  {
    echo "=== php-fpm ==="
    systemctl is-active php8.3-fpm 2>/dev/null || systemctl is-active php-fpm 2>/dev/null || echo inactive
    echo "=== nginx ==="
    systemctl is-active nginx 2>/dev/null || echo inactive
    echo "=== mariadb ==="
    systemctl is-active mariadb 2>/dev/null || systemctl is-active mysql 2>/dev/null || echo inactive
    echo "=== socket ==="
    ls -la "${PHP_SOCKET:-?}" 2>/dev/null || true
    echo "=== nginx -t ==="
    nginx -t 2>&1 || true
    echo "=== artisan about ==="
    (cd "$PANEL_DIR" && php artisan about --no-interaction 2>&1) || true
    echo "=== laravel.log ==="
    [ -f "$log" ] && tail -n 40 "$log" || echo "(no log)"
  } >>"$LOG_PATH" 2>&1
}

hkz_panel_heal() {
  hkz_resolve_panel_dir 2>/dev/null || true
  [ -f "${PANEL_DIR}/artisan" ] || return 1
  hkz_panel_load_install_secrets 2>/dev/null || true
  hkz_set_web_user 2>/dev/null || true
  hkz_resolve_php_fpm_env 2>/dev/null || true
  hkz_panel_ensure_app_key || msg_warn "$(hkz_t panel_heal_key_fail)"
  hkz_panel_ensure_app_url || true
  hkz_panel_ensure_settings_ui || true
  hkz_panel_ensure_service_author || true
  hkz_panel_ensure_db_connection || msg_warn "$(hkz_t panel_heal_db_fail)"
  hkz_panel_fix_permissions || return 1
  hkz_panel_artisan_clear_caches
  (
    cd "$PANEL_DIR"
    php artisan migrate --force --no-interaction >>"$LOG_PATH" 2>&1
  ) || msg_warn "$(hkz_t panel_heal_migrate_fail)"
  hkz_panel_ensure_drivers || true
  hkz_panel_mail_log 2>/dev/null || true
  if [ -n "${user_email:-}" ] && [ -n "${user_password:-}" ]; then
    hkz_panel_ensure_admin_user >>"$LOG_PATH" 2>&1 || msg_warn "$(hkz_t panel_admin_fail)"
  fi
  chown -R "${WEB_USER}:${WEB_GROUP}" "${PANEL_DIR}" 2>/dev/null || true
  systemctl enable --now pteroq >>"$LOG_PATH" 2>&1 || true
  systemctl restart pteroq >>"$LOG_PATH" 2>&1 || true
  return 0
}

hkz_panel_finalize() {
  local attempt=1 max=3
  msg_step "$(hkz_t panel_finalize)"
  while [ "$attempt" -le "$max" ]; do
    hkz_panel_heal || true
    hkz_ensure_php_fpm >>"$LOG_PATH" 2>&1 || true
    hkz_nginx_sync_php_socket || true
    hkz_ensure_panel_services || return 1
    if hkz_panel_artisan_boot_test && hkz_panel_http_probe; then
      msg_ok "$(hkz_t panel_heal_ok)"
      return 0
    fi
    [ "$attempt" -lt "$max" ] && msg_warn "$(hkz_t panel_heal_retry) ${attempt}/${max}"
    attempt=$((attempt + 1))
    sleep 2
  done
  hkz_panel_dump_diagnostics
  msg_warn "$(hkz_t panel_heal_warn) ${LOG_PATH}"
  return 1
}
