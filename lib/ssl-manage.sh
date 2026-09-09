#!/bin/bash

hkz_ssl_nginx_conf() {
  local c
  for c in \
    "${NGINX_AVAIL:-/etc/nginx/sites-available}/pterodactyl.conf" \
    /etc/nginx/sites-available/pterodactyl.conf \
    /etc/nginx/conf.d/pterodactyl.conf; do
    [ -f "$c" ] && echo "$c" && return 0
  done
  return 1
}

hkz_ssl_detect_domain() {
  local d conf
  d=$(hkz_panel_env_val APP_URL 2>/dev/null | sed -E 's#https?://##; s#/.*##; s/[[:space:]]//g')
  if [ -n "$d" ] && [ "$d" != "localhost" ] && ! hkz_fqdn_is_ip "$d" 2>/dev/null; then
    echo "$d"
    return 0
  fi
  conf=$(hkz_ssl_nginx_conf 2>/dev/null) || conf=""
  if [ -n "$conf" ]; then
    d=$(awk '/server_name/ { print $2; exit }' "$conf" | tr -d ';\r')
    if [ -n "$d" ] && [ "$d" != "_" ] && [ "$d" != "localhost" ] && ! hkz_fqdn_is_ip "$d" 2>/dev/null; then
      echo "$d"
      return 0
    fi
  fi
  if [ -n "${FQDN:-}" ] && ! hkz_fqdn_is_ip "$FQDN" 2>/dev/null; then
    echo "$FQDN"
    return 0
  fi
  return 1
}

hkz_ssl_cert_dir() {
  local domain="${1:-}"
  [ -n "$domain" ] || return 1
  [ -d "/etc/letsencrypt/live/${domain}" ] && echo "/etc/letsencrypt/live/${domain}" && return 0
  return 1
}

hkz_ssl_write_nginx() {
  local mode="$1" domain="$2" tpl conf
  hkz_resolve_php_fpm_env || return 1
  hkz_ensure_php_fpm 2>/dev/null || true
  hkz_detect_php_socket 2>/dev/null || true
  [ -n "${PANEL_DIR:-}" ] || hkz_resolve_panel_dir 2>/dev/null || true
  [ -f "${PANEL_DIR}/artisan" ] || { msg_err "$(hkz_t ssl_panel_missing)"; return 1; }
  [ -n "$domain" ] || return 1

  if [ "$mode" = ssl ]; then
    tpl="${CONFIGS_DIR}/nginx_ssl.conf"
  else
    tpl="${CONFIGS_DIR}/nginx.conf"
  fi
  [ -f "$tpl" ] || { msg_err "$(hkz_t ssl_tpl_missing)"; return 1; }

  conf="${NGINX_AVAIL}/pterodactyl.conf"
  if [ "$OS" = rocky ] || [ "$OS" = almalinux ]; then
    conf="${NGINX_AVAIL}/pterodactyl.conf"
  fi

  cp "$tpl" "$conf"
  sed -i "s|@FQDN@|${domain}|g" "$conf"
  sed -i "s|@PHP_SOCKET@|${PHP_SOCKET}|g" "$conf"
  sed -i "s|@PANEL_DIR@|${PANEL_DIR}|g" "$conf"

  if [ "$OS" = ubuntu ] || [ "$OS" = debian ]; then
    mkdir -p "${NGINX_ENABL}"
    ln -sf "$conf" "${NGINX_ENABL}/pterodactyl.conf"
    rm -f "${NGINX_ENABL}/default" 2>/dev/null || true
  fi

  nginx -t >>"${LOG_PATH:-/dev/null}" 2>&1 || {
    msg_err "$(hkz_t ssl_nginx_test_fail)"
    return 1
  }
  systemctl enable nginx >>"${LOG_PATH:-/dev/null}" 2>&1 || true
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
  return 0
}

hkz_ssl_set_app_url() {
  local scheme="$1" domain="$2" env="${PANEL_DIR}/.env"
  [ -f "$env" ] || return 1
  [ -n "$domain" ] || return 1
  hkz_panel_env_set "$env" APP_URL "${scheme}://${domain}"
  hkz_panel_artisan_clear_caches 2>/dev/null || true
  return 0
}

hkz_ssl_ensure_certbot() {
  if command -v certbot >/dev/null 2>&1 && certbot plugins 2>/dev/null | grep -qi nginx; then
    return 0
  fi
  msg_step "$(hkz_t ssl_install_certbot)"
  case "$OS" in
    ubuntu|debian) install_packages certbot python3-certbot-nginx || return 1 ;;
    rocky|almalinux) install_packages certbot python3-certbot-nginx || install_packages certbot || return 1 ;;
    *) return 1 ;;
  esac
  return 0
}

hkz_ssl_status() {
  local domain conf live expiry app_url nginx_ssl=0
  msg_step "$(hkz_t ssl_status_title)"

  domain=$(hkz_ssl_detect_domain 2>/dev/null) || domain=""
  if [ -z "$domain" ]; then
    msg_warn "$(hkz_t ssl_no_domain)"
  else
    msg_info "$(hkz_t ssl_domain): ${domain}"
  fi

  app_url=$(hkz_panel_env_val APP_URL 2>/dev/null || echo "?")
  msg_info "APP_URL: ${app_url}"

  conf=$(hkz_ssl_nginx_conf 2>/dev/null) || conf=""
  if [ -n "$conf" ]; then
    msg_info "nginx: ${conf}"
    if grep -qE 'listen[[:space:]]+443|ssl_certificate' "$conf" 2>/dev/null; then
      nginx_ssl=1
      msg_ok "$(hkz_t ssl_nginx_https)"
    else
      msg_info "$(hkz_t ssl_nginx_http)"
    fi
  else
    msg_warn "$(hkz_t ssl_nginx_missing)"
  fi

  if [ -n "$domain" ] && live=$(hkz_ssl_cert_dir "$domain"); then
    msg_ok "$(hkz_t ssl_cert_present): ${live}"
    if [ -f "${live}/fullchain.pem" ]; then
      expiry=$(openssl x509 -in "${live}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2-)
      [ -n "$expiry" ] && msg_info "$(hkz_t ssl_cert_expiry): ${expiry}"
      openssl x509 -in "${live}/fullchain.pem" -noout -subject -issuer 2>/dev/null | while IFS= read -r line; do
        msg_info "$line"
      done
    fi
  elif [ -n "$domain" ]; then
    msg_warn "$(hkz_t ssl_cert_missing)"
  fi

  if command -v certbot >/dev/null 2>&1; then
    msg_info "$(hkz_t ssl_certbot_list)"
    certbot certificates 2>/dev/null | sed 's/^/  /' || true
  else
    msg_warn "$(hkz_t ssl_certbot_missing)"
  fi

  if [ "$nginx_ssl" = 1 ] && [ -n "$domain" ] && [ ! -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
    msg_err "$(hkz_t ssl_mismatch)"
  fi
  return 0
}

hkz_ssl_issue_panel() {
  local domain mail="${1:-}" rc
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && return 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  hkz_panel_files_exist || { msg_err "$(hkz_t ssl_panel_missing)"; return 1; }

  domain=$(hkz_ssl_detect_domain 2>/dev/null) || domain=""
  if [ -z "$domain" ] || hkz_fqdn_is_ip "$domain" 2>/dev/null; then
    required_input domain "$(hkz_t ssl_ask_domain)" "$(hkz_t input_required)"
  fi
  if hkz_fqdn_is_ip "$domain" 2>/dev/null; then
    msg_err "$(hkz_t ssl_ip_not_allowed)"
    return 1
  fi

  if [ -z "$mail" ]; then
    email_input mail "$(hkz_t ui_ssl_email)" "$(hkz_t ui_bad_email)"
  fi

  export FQDN="$domain"
  hkz_ssl_ensure_certbot || return 1

  if [ ! -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
    msg_step "$(hkz_t ssl_prepare_http)"
    hkz_ssl_write_nginx http "$domain" || return 1
  fi

  msg_step "$(hkz_t ssl_issue)"
  set +e
  if [ -n "$mail" ]; then
    certbot --nginx --redirect --non-interactive --agree-tos --no-eff-email --email "$mail" -d "$domain" 2>&1 | tee -a "${LOG_PATH:-/dev/null}"
    rc=${PIPESTATUS[0]}
  else
    certbot --nginx --redirect --non-interactive --agree-tos --register-unsafely-without-email -d "$domain" 2>&1 | tee -a "${LOG_PATH:-/dev/null}"
    rc=${PIPESTATUS[0]}
  fi
  set -e

  if [ "${rc:-1}" -ne 0 ] || [ ! -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
    msg_err "$(hkz_t panel_ssl_fail)"
    return 1
  fi

  hkz_ssl_write_nginx ssl "$domain" || return 1
  hkz_ssl_set_app_url https "$domain"
  msg_ok "$(hkz_t panel_ssl_ok)"
  msg_info "https://${domain}"
  return 0
}

hkz_ssl_renew_panel() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && return 1
  hkz_ssl_ensure_certbot || return 1
  msg_step "$(hkz_t ssl_renew)"
  if certbot renew --nginx --non-interactive 2>&1 | tee -a "${LOG_PATH:-/dev/null}"; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx
    msg_ok "$(hkz_t ssl_renew_ok)"
    return 0
  fi
  msg_err "$(hkz_t ssl_renew_fail)"
  return 1
}

hkz_ssl_remove_panel() {
  local domain conf ans
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && return 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  hkz_panel_files_exist || { msg_err "$(hkz_t ssl_panel_missing)"; return 1; }

  domain=$(hkz_ssl_detect_domain 2>/dev/null) || domain=""
  if [ -z "$domain" ]; then
    required_input domain "$(hkz_t ssl_ask_domain)" "$(hkz_t input_required)"
  fi

  echo -en "  $(hkz_t ssl_remove_confirm) [${domain}] (y/N): "
  read -r ans
  [[ "$ans" =~ ^[Yy] ]] || { msg_info "$(hkz_t ssl_cancelled)"; return 0; }

  msg_step "$(hkz_t ssl_remove)"
  hkz_ssl_write_nginx http "$domain" || return 1
  hkz_ssl_set_app_url http "$domain"

  echo -en "  $(hkz_t ssl_delete_le) (y/N): "
  read -r ans
  if [[ "$ans" =~ ^[Yy] ]] && command -v certbot >/dev/null 2>&1; then
    certbot delete --cert-name "$domain" --non-interactive 2>&1 | tee -a "${LOG_PATH:-/dev/null}" || true
  fi

  msg_ok "$(hkz_t ssl_remove_ok)"
  msg_info "http://${domain}"
  return 0
}
