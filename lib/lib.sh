#!/bin/bash

set -e

export INSTALLER_NAME="HKZPterodactylInstaller"
export HKZ_INSTALLER_REPO="${HKZ_INSTALLER_REPO:-hakyzmain/HKZPterodactylInstaller}"
export HKZ_INSTALLER_BRANCH="${HKZ_INSTALLER_BRANCH:-main}"
export HKZ_OPT_DIR="${HKZ_OPT_DIR:-/opt/HKZPterodactylInstaller}"
export HKZ_LEGACY_OPT_DIRS="/opt/phkz /opt/HKZPanelAutoInstaller"
export HKZ_INSTALL_DIR="${HKZ_INSTALL_DIR:-}"
export HKZ_INSTALLER_RAW="${HKZ_INSTALLER_RAW:-https://raw.githubusercontent.com/${HKZ_INSTALLER_REPO}/${HKZ_INSTALLER_BRANCH}/install.sh}"
export HKZ_SHORT_RAW="${HKZ_SHORT_RAW:-https://raw.githubusercontent.com/${HKZ_INSTALLER_REPO}/${HKZ_INSTALLER_BRANCH}/run.sh}"
export HKZ_INSTALLER_REV="${HKZ_INSTALLER_REV:-109}"
export HKZ_STAMP_DIR="/var/lib/phkz"
export HKZ_STAMP_THEME="${HKZ_STAMP_DIR}/hkz-aurora-theme"
export HKZ_STAMP_PANEL="${HKZ_STAMP_DIR}/panel"
export HKZ_STAMP_WINGS="${HKZ_STAMP_DIR}/wings"
export WINGS_DL_BASE_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_"

_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "${_LIB_ROOT}/VERSION" ]; then
  INSTALLER_VERSION=$(tr -d '[:space:]' <"${_LIB_ROOT}/VERSION")
else
  INSTALLER_VERSION="${INSTALLER_VERSION:-1.4.0}"
fi
export INSTALLER_VERSION
export PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
export PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
export LOG_PATH="/var/log/HKZPterodactylInstaller.log"

export C_RESET='\033[0m'
export C_BOLD='\033[1m'
export C_DIM='\033[2m'
export C_PURPLE='\033[0;35m'
export C_CYAN='\033[0;36m'
export C_BLUE='\033[0;34m'
export C_GREEN='\033[0;32m'
export C_YELLOW='\033[1;33m'
export C_RED='\033[0;31m'

email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"
password_charset='A-Za-z0-9!"#%&()*+,-./:;<=>?@[\]^_`{|}~'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

lib_loaded() { return 0; }

hkz_init_install_dir() {
  local leg
  if [ -n "${HKZ_INSTALL_DIR:-}" ]; then
    return 0
  fi
  if [ -d "$HKZ_OPT_DIR" ]; then
    export HKZ_INSTALL_DIR="$HKZ_OPT_DIR"
    return 0
  fi
  for leg in $HKZ_LEGACY_OPT_DIRS; do
    if [ -d "$leg" ]; then
      export HKZ_INSTALL_DIR="$leg"
      return 0
    fi
  done
  export HKZ_INSTALL_DIR="$HKZ_OPT_DIR"
}

hkz_migrate_install_paths() {
  local leg
  rm -rf /opt/PterodactylHKZAutoInstaller 2>/dev/null || true
  for leg in $HKZ_LEGACY_OPT_DIRS; do
    if [ -d "$leg" ] && [ ! -e "$HKZ_OPT_DIR" ]; then
      ln -sfn "$leg" "$HKZ_OPT_DIR" 2>/dev/null || true
      break
    fi
  done
  for f in /var/log/phkz.log /var/log/HKZPanelAutoInstaller.log; do
    if [ -f "$f" ] && [ ! -f "$LOG_PATH" ]; then
      ln -sfn "$f" "$LOG_PATH" 2>/dev/null || true
      break
    fi
  done
}

hkz_init_install_dir
hkz_migrate_install_paths

resolve_github_token() {
  GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  [ -z "$GITHUB_TOKEN" ] && [ -f /root/.phkz_github_token ] && GITHUB_TOKEN=$(tr -d '[:space:]' </root/.phkz_github_token)
  [ -z "$GITHUB_TOKEN" ] && command -v gh >/dev/null 2>&1 && GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
  export GITHUB_TOKEN
}

hkz_fix_script() {
  local f="$1"
  [ -f "$f" ] && sed -i 's/\r$//' "$f" 2>/dev/null || sed -i '' 's/\r$//' "$f" 2>/dev/null || true
}

hkz_mark_panel() { mkdir -p "$HKZ_STAMP_DIR"; date -Iseconds >"$HKZ_STAMP_PANEL"; }
hkz_mark_wings() { mkdir -p "$HKZ_STAMP_DIR"; date -Iseconds >"$HKZ_STAMP_WINGS"; }

hkz_panel_dir_from_nginx() {
  local f root d
  for f in /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf \
    /etc/nginx/conf.d/pterodactyl.conf /etc/nginx/sites-enabled/*pterodactyl* \
    /etc/nginx/sites-available/*pterodactyl*; do
    [ -f "$f" ] || continue
    root=$(grep -E '^\s*root\s+' "$f" 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';"')
    [ -z "$root" ] && continue
    d="${root%/public}"
    [ -f "${d}/artisan" ] && { echo "$(cd "$d" && pwd)"; return 0; }
    [ -f "${root}/../artisan" ] && { echo "$(cd "$(dirname "$root")" && pwd)"; return 0; }
  done
  return 1
}

hkz_resolve_panel_dir() {
  local try found
  if [ -f "${PANEL_DIR}/artisan" ]; then
    PANEL_DIR="$(cd "$PANEL_DIR" && pwd)"
    export PANEL_DIR
    return 0
  fi
  for try in /var/www/pterodactyl /var/www/html/pterodactyl /srv/pterodactyl; do
    if [ -f "${try}/artisan" ]; then
      PANEL_DIR="$(cd "$try" && pwd)"
      export PANEL_DIR
      return 0
    fi
  done
  found=$(hkz_panel_dir_from_nginx) || true
  if [ -n "$found" ] && [ -f "${found}/artisan" ]; then
    PANEL_DIR="$found"
    export PANEL_DIR
    return 0
  fi
  return 1
}

hkz_is_pterodactyl_panel() {
  local d="${1:-$PANEL_DIR}"
  [ -f "${d}/artisan" ] || return 1
  grep -q 'Pterodactyl\\Panel' "${d}/artisan" 2>/dev/null && return 0
  [ -f "${d}/composer.json" ] && grep -qi 'pterodactyl/panel' "${d}/composer.json" 2>/dev/null && return 0
  [ -f "${d}/app/Models/User.php" ] && return 0
  return 1
}

hkz_panel_installed_by_us() {
  [ -f "$HKZ_STAMP_PANEL" ]
}

hkz_wings_installed_by_us() {
  [ -f "$HKZ_STAMP_WINGS" ]
}

hkz_panel_external_install() {
  hkz_resolve_panel_dir 2>/dev/null || true
  [ -f "${PANEL_DIR}/artisan" ] && ! hkz_panel_installed_by_us
}

hkz_panel_core_ok() {
  local d="${1:-$PANEL_DIR}"
  [ -f "${d}/artisan" ] || return 1
  [ -f "${d}/public/index.php" ] || return 1
  [ -f "${d}/resources/views/layouts/admin.blade.php" ] || return 1
  [ -d "${d}/app" ] || return 1
  [ -d "${d}/resources/views" ] || return 1
}

hkz_panel_files_exist() {
  hkz_resolve_panel_dir 2>/dev/null || true
  hkz_is_pterodactyl_panel && return 0
  [ -f "${PANEL_DIR}/artisan" ] && return 0
  return 1
}

hkz_ensure_wings_etc() {
  mkdir -p /etc/pterodactyl /var/run/wings /var/lib/pterodactyl
  chmod 755 /etc/pterodactyl /var/run/wings 2>/dev/null || true
}

hkz_wings_bin() {
  if [ -x /usr/local/bin/wings ]; then
    printf '%s' /usr/local/bin/wings
    return 0
  fi
  if [ -x /usr/bin/wings ]; then
    printf '%s' /usr/bin/wings
    return 0
  fi
  return 1
}

hkz_wings_link_binary() {
  local bin
  bin=$(hkz_wings_bin 2>/dev/null) || return 1
  ln -sf "$bin" /usr/bin/wings 2>/dev/null || true
  ln -sf "$bin" /usr/local/bin/wings 2>/dev/null || true
  chmod 755 "$bin" 2>/dev/null || true
}

hkz_wings_ensure_binary() {
  local url dest arch
  hkz_wings_bin >/dev/null 2>&1 && { hkz_wings_link_binary; return 0; }
  [ -z "${ARCH:-}" ] && detect_os 2>/dev/null || true
  arch="${ARCH:-amd64}"
  url="${WINGS_DL_BASE_URL}${arch}"
  dest=/usr/local/bin/wings
  msg_step "$(hkz_t wings_install_bin)"
  hkz_ensure_wings_etc
  log "[wings] download: $url"
  hkz_fetch_url "$url" "$dest" || {
    msg_err "$(hkz_t wings_install_bin_fail)"
    return 1
  }
  chmod 755 "$dest"
  hkz_wings_link_binary
  msg_ok "$(hkz_t wings_dl_ok)"
  return 0
}

hkz_wings_normalize_deploy_cmd() {
  local cmd="$1" bin
  bin=$(hkz_wings_bin 2>/dev/null) || bin=/usr/local/bin/wings
  printf '%s' "$cmd" | sed -E \
    -e 's#cd[[:space:]]+/etc/pterodactyl[[:space:]]*&&[[:space:]]*##' \
    -e "s#(^|[;&|[:space:]])(sudo[[:space:]]+)?wings([[:space:]]+)#\1\2${bin}\3#g" \
    -e "s#^sudo[[:space:]]+${bin}#${bin}#g"
}

hkz_wings_config_path() {
  local f
  for f in /etc/pterodactyl/config.yml /etc/pterodactyl/config.yaml; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

hkz_wings_ssl_cert_path() {
  local cfg="$1"
  awk '
    /^api:/ { in_api = 1 }
    in_api && /^  ssl:/ { in_ssl = 1 }
    in_ssl && /^    cert:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      print
      exit
    }
  ' "$cfg"
}

hkz_wings_ssl_enabled() {
  local cfg="$1"
  awk '
    /^api:/ { in_api = 1 }
    in_api && /^  ssl:/ { in_ssl = 1 }
    in_ssl && /^    enabled:[[:space:]]*true/ { print "1"; exit }
    in_ssl && /^  [a-zA-Z]/ && !/^  ssl:/ { in_ssl = 0 }
  ' "$cfg"
}

hkz_wings_cert_domain() {
  basename "$(dirname "$1")"
}

hkz_wings_open_cert_ports() {
  command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active && {
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
  }
  command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1 && {
    firewall-cmd --permanent --add-service=http 2>/dev/null || true
    firewall-cmd --permanent --add-service=https 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
  }
}

hkz_wings_show_cert_files() {
  local domain="$1" f
  for f in fullchain.pem privkey.pem cert.pem; do
    [ -f "/etc/letsencrypt/live/${domain}/${f}" ] && echo -e "  ${C_DIM}/etc/letsencrypt/live/${domain}/${f}${C_RESET}"
  done
}

hkz_wings_nginx_paths() {
  case "${OS:-}" in
    ubuntu|debian)
      NGINX_AVAIL=/etc/nginx/sites-available
      NGINX_ENABL=/etc/nginx/sites-enabled
      ;;
    rocky|almalinux)
      NGINX_AVAIL=/etc/nginx/conf.d
      NGINX_ENABL=/etc/nginx/conf.d
      ;;
    *)
      return 1
      ;;
  esac
  export NGINX_AVAIL NGINX_ENABL
}

hkz_wings_ensure_certbot_nginx() {
  [ -z "${OS:-}" ] && detect_os 2>/dev/null || true
  if command -v certbot >/dev/null 2>&1 && certbot plugins 2>/dev/null | grep -qi nginx; then
    return 0
  fi
  msg_step "$(hkz_t wings_ssl_install_certbot)"
  case "${OS:-}" in
    ubuntu|debian|rocky|almalinux)
      install_packages certbot python3-certbot-nginx || return 1
      ;;
    *)
      install_packages certbot || return 1
      ;;
  esac
}

hkz_wings_configure_nginx() {
  local domain="$1" conf tpl
  [ -n "$domain" ] || return 1
  hkz_wings_nginx_paths || return 1
  tpl="${CONFIGS_DIR:-}/nginx-wings.conf"
  [ -f "$tpl" ] || tpl="$(dirname "${BASH_SOURCE[0]}")/../configs/nginx-wings.conf"
  [ -f "$tpl" ] || return 1
  conf="${NGINX_AVAIL}/wings-node.conf"
  cp "$tpl" "$conf"
  sed -i "s|@FQDN@|${domain}|g" "$conf"
  if [ "${OS:-}" = ubuntu ] || [ "${OS:-}" = debian ]; then
    ln -sf "$conf" "${NGINX_ENABL}/wings-node.conf"
  fi
  command -v nginx >/dev/null 2>&1 || install_packages nginx || return 1
  nginx -t
  systemctl enable nginx 2>/dev/null || true
  systemctl restart nginx
}

hkz_wings_setup_node_ssl() {
  local domain="$1" mail="$2" rc certbot_cmd=()
  [ -n "$domain" ] || return 1
  hkz_fqdn_is_ip "$domain" && return 1
  if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
    msg_ok "$(hkz_t wings_ssl_exists) ${domain}"
    hkz_wings_show_cert_files "$domain"
    return 0
  fi
  [ -z "$mail" ] && mail="${WINGS_EMAIL:-${EMAIL:-}}"
  msg_step "SSL"
  hkz_wings_open_cert_ports
  hkz_wings_ensure_certbot_nginx || return 1
  hkz_wings_configure_nginx "$domain" || return 1
  if [ -n "$mail" ]; then
    certbot_cmd=(certbot --nginx --redirect --non-interactive --agree-tos --no-eff-email --email "$mail" -d "$domain")
    echo -e "  ${C_DIM}certbot --nginx -d ${domain} --email ${mail}${C_RESET}"
  else
    certbot_cmd=(certbot --nginx --redirect --non-interactive --agree-tos --register-unsafely-without-email -d "$domain")
    echo -e "  ${C_DIM}certbot --nginx -d ${domain}${C_RESET}"
  fi
  echo ""
  set -o pipefail
  if [ -n "${LOG_PATH:-}" ]; then
    "${certbot_cmd[@]}" 2>&1 | tee -a "$LOG_PATH"
  else
    "${certbot_cmd[@]}"
  fi
  rc=$?
  set +o pipefail
  systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true
  if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
    msg_ok "$(hkz_t wings_ssl_issue_ok) ${domain}"
    hkz_wings_show_cert_files "$domain"
    return 0
  fi
  log "[wings] certbot --nginx exit=$rc domain=$domain"
  msg_err "$(hkz_t wings_ssl_cert_fail)"
  return 1
}

hkz_wings_issue_cert() {
  hkz_wings_setup_node_ssl "$1" "$2"
}

hkz_wings_disable_ssl() {
  local cfg="$1" tmp
  [ -n "$cfg" ] && [ -f "$cfg" ] || return 1
  [ -n "$(hkz_wings_ssl_enabled "$cfg")" ] || return 0
  tmp=$(mktemp)
  awk '
    /^api:/ { in_api = 1 }
    in_api && /^  ssl:/ { in_ssl = 1 }
    in_ssl && /^    enabled:/ {
      sub(/true/, "false")
      print
      next
    }
    in_ssl && /^  [a-zA-Z]/ && !/^  ssl:/ { in_ssl = 0 }
    { print }
  ' "$cfg" >"$tmp" && mv -f "$tmp" "$cfg"
  msg_info "$(hkz_t wings_ssl_disabled)"
}

hkz_wings_fix_config_ssl() {
  local cfg cert
  cfg=$(hkz_wings_config_path 2>/dev/null) || return 0
  [ -n "$cfg" ] || return 0
  [ -n "$(hkz_wings_ssl_enabled "$cfg")" ] || return 0
  cert=$(hkz_wings_ssl_cert_path "$cfg")
  [ -n "$cert" ] && [ -f "$cert" ] && return 0
  hkz_wings_disable_ssl "$cfg"
}

hkz_wings_ssl_domain() {
  local cfg cert domain=""
  cfg=$(hkz_wings_config_path 2>/dev/null) || cfg=""
  if [ -n "$cfg" ]; then
    cert=$(hkz_wings_ssl_cert_path "$cfg" 2>/dev/null)
    [ -n "$cert" ] && domain=$(hkz_wings_cert_domain "$cert")
  fi
  [ -n "$domain" ] && echo "$domain" && return 0
  [ -n "${WINGS_FQDN:-}" ] && echo "${WINGS_FQDN}" && return 0
  return 1
}

hkz_wings_ensure_node_cert() {
  local domain mail
  mail="${WINGS_EMAIL:-${EMAIL:-}}"
  domain=$(hkz_wings_ssl_domain 2>/dev/null) || domain=""
  [ -n "$domain" ] || return 0
  hkz_fqdn_is_ip "$domain" && return 0
  if hkz_wings_setup_node_ssl "$domain" "$mail"; then
    return 0
  fi
  hkz_wings_fix_config_ssl
  return 1
}

hkz_wings_start() {
  systemctl reset-failed wings 2>>"${LOG_PATH:-/dev/null}" || true
  systemctl enable wings 2>>"${LOG_PATH:-/dev/null}" || true
  systemctl restart wings 2>>"${LOG_PATH:-/dev/null}" || systemctl start wings 2>>"${LOG_PATH:-/dev/null}"
}

hkz_wings_run_deploy() {
  local cmd="$1" fixed
  [ -n "$cmd" ] || return 0
  hkz_ensure_wings_etc
  hkz_wings_ensure_binary || return 1
  hkz_wings_link_binary || true
  fixed=$(hkz_wings_normalize_deploy_cmd "$cmd")
  log "[wings] deploy: $fixed"
  ( cd /etc/pterodactyl && bash -c "$fixed" )
  return $?
}

hkz_wings_files_exist() {
  [ -x /usr/local/bin/wings ] && return 0
  [ -f /etc/systemd/system/wings.service ] && return 0
  [ -f /etc/pterodactyl/config.yml ] && return 0
  [ -f /etc/pterodactyl/config.yaml ] && return 0
  [ -d /etc/pterodactyl ] && [ -n "$(ls -A /etc/pterodactyl 2>/dev/null)" ] && return 0
  [ -d /var/lib/pterodactyl/volumes ] && return 0
  [ -d /var/lib/pterodactyl ] && return 0
  return 1
}

hkz_panel_report_detect() {
  hkz_resolve_panel_dir 2>/dev/null || true
  if ! hkz_panel_files_exist; then
    return 1
  fi
  msg_info "$(hkz_t detect_panel_dir) ${PANEL_DIR}"
  [ -f "${PANEL_DIR}/artisan" ] && msg_ok "artisan"
  [ -f "${PANEL_DIR}/.env" ] && msg_ok ".env"
  [ -f "${PANEL_DIR}/public/index.php" ] && msg_ok "public/index.php"
  if hkz_panel_external_install; then
    msg_info "$(hkz_t panel_external_manage)"
  elif hkz_panel_installed_by_us; then
    msg_info "$(hkz_t panel_installed_by_us)"
  fi
  return 0
}

hkz_has_panel() { hkz_panel_files_exist; }
hkz_has_wings() { hkz_wings_files_exist; }

hkz_set_web_user() {
  [ -n "${OS:-}" ] || detect_os
  case "$OS" in
    ubuntu|debian) export WEB_USER=www-data WEB_GROUP=www-data ;;
    rocky|almalinux) export WEB_USER=nginx WEB_GROUP=nginx ;;
    *) msg_err "$(hkz_t err_os_panel) ${OS:-?}"; return 1 ;;
  esac
  return 0
}

hkz_panel_ready_for_theme() {
  [ -f "${PANEL_DIR}/artisan" ]
}

hkz_theme_catalog_file() {
  echo "${HKZ_INSTALL_DIR:-${SCRIPT_DIR:-${HKZ_OPT_DIR}}}/theme/catalog.conf"
}

hkz_theme_name_by_id() {
  local id="$1" line
  line=$(grep -E "^${id}\|" "$(hkz_theme_catalog_file)" 2>/dev/null | head -1)
  [ -n "$line" ] && echo "${line#*|}" || echo "HKZ $id"
}

hkz_blade_has_theme_marker() {
  local f="${1:-${PANEL_DIR}/resources/views/templates/wrapper.blade.php}"
  [ -f "$f" ] || return 1
  grep -qE 'data-hkz-theme-begin|HKZ-AURORA-THEME-BEGIN' "$f" 2>/dev/null
}

hkz_hkztheme_active() {
  [ -f "$HKZ_STAMP_THEME" ] && [ -s "$HKZ_STAMP_THEME" ] && return 0
  [ -f "${PANEL_DIR}/public/assets/hkz/active/client.css" ] && hkz_blade_has_theme_marker && return 0
  return 1
}

hkz_theme_current_label() {
  local id
  if ! hkz_hkztheme_active; then
    hkz_t theme_std_ptero
    return 0
  fi
  id=$(tr -d '[:space:]' <"$HKZ_STAMP_THEME" 2>/dev/null)
  [ -z "$id" ] && [ -f "${PANEL_DIR}/public/assets/hkz/active/client.css" ] && id=aurora
  [ -n "$id" ] && hkz_theme_name_by_id "$id" || hkz_t theme_hkz_generic
}

hkz_theme_pending_label() {
  case "${HKZ_THEME_CMD:-}" in
    default|standard|std|remove) hkz_t theme_std_no_hkz ;;
    *)
      local id="${HKZ_THEME_ID:-$HKZ_THEME_CMD}"
      id=$(echo "$id" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
      [ -n "$id" ] && hkz_theme_name_by_id "$id" || hkz_t theme_hkz_generic
      ;;
  esac
}

hkz_ensure_theme_pack() {
  local src="${1:-$SCRIPT_DIR}"
  local dest="${HKZ_INSTALL_DIR:-$HKZ_OPT_DIR}"
  if [ ! -f "${src}/theme/catalog.conf" ]; then
    msg_err "$(hkz_t err_theme_catalog) ${src}/theme/catalog.conf"
    return 1
  fi
  mkdir -p "${dest}/theme"
  cp -a "${src}/theme/." "${dest}/theme/"
  msg_ok "$(hkz_t ok_theme_pack) ${dest}/theme/"
  return 0
}

hkz_installer_has_legacy_nebula() {
  local dir="${1:-${HKZ_INSTALL_DIR:-$HKZ_OPT_DIR}}"
  [ -d "${dir}/assets" ] && return 0
  grep -rqi 'nebula' "${dir}/lib" "${dir}/installers" "${dir}/run.sh" "${dir}/install.sh" 2>/dev/null && return 0
  return 1
}

log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_PATH" 2>/dev/null || true
}

draw_logo() {
  local logo="${SCRIPT_DIR}/lib/logo.ascii"
  echo -e "${C_PURPLE}${C_BOLD}"
  if [ -f "$logo" ]; then
    sed 's/[[:space:]]*$//' "$logo"
  else
    printf '%s\n' \
      ' _  _ _  __ _______ _                   _         _        _ ___         _        _ _         ' \
      '| || | |/ /|_  / _ \ |_ ___ _ _ ___  __| |__ _ __| |_ _  _| |_ _|_ _  __| |_ __ _| | |___ _ _ ' \
      '| __ | '"'"' <  / /|  _/  _/ -_) '"'"'_/ _ \/ _` / _` / _|  _| || | || || '"'"' \(_-<  _/ _` | | / -_) '"'"'_|' \
      '|_||_|_|\_\/___|_|  \__\___|_| \___/\__,_\__,_\__|\__|\_, |_|___|_||_/__/\__\__,_|_|_\___|_|  ' \
      '                                                      |__/                                     '
  fi
  echo -e "${C_RESET}${C_DIM}  v${INSTALLER_VERSION}${C_RESET}"
  echo ""
}

msg_info()    { echo -e "  ${C_CYAN}>${C_RESET} $*"; log "INFO: $*"; }
msg_ok()      { echo -e "  ${C_GREEN}+${C_RESET} $*"; log "OK: $*"; }
msg_warn()    { echo -e "  ${C_YELLOW}!${C_RESET} $*"; log "WARN: $*"; }
msg_err()     { echo -e "  ${C_RED}x${C_RESET} $*" >&2; log "ERR: $*"; }
msg_step()    { echo -e "\n  ${C_BOLD}:: $*${C_RESET}\n"; }

_I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${_I18N_DIR}/i18n.sh" ] && . "${_I18N_DIR}/i18n.sh"

print_rule() {
  echo "  ----------------------------------------"
}

get_latest_release() {
  curl -fsSL -H "User-Agent: HKZPterodactylInstaller" \
    "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
    grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

hkz_curl_fetch() {
  local url="$1" dest="$2"
  [ -n "$url" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsSL --max-time 180 --connect-timeout 30 \
    --retry 3 --retry-delay 3 \
    -H "User-Agent: HKZPterodactylInstaller/${INSTALLER_VERSION:-dev}" \
    -o "$dest" "$url" 2>>"${LOG_PATH:-/dev/null}"
}

hkz_wget_fetch() {
  local url="$1" dest="$2"
  [ -n "$url" ] || return 1
  command -v wget >/dev/null 2>&1 || return 1
  wget -q --timeout=30 --tries=3 --user-agent="HKZPterodactylInstaller" \
    -O "$dest" "$url" 2>>"${LOG_PATH:-/dev/null}"
}

hkz_fetch_url() {
  local url="$1" dest="$2"
  rm -f "$dest" 2>/dev/null || true
  hkz_curl_fetch "$url" "$dest" && [ -s "$dest" ] && return 0
  rm -f "$dest" 2>/dev/null || true
  hkz_wget_fetch "$url" "$dest" && [ -s "$dest" ] && return 0
  rm -f "$dest" 2>/dev/null || true
  return 1
}

hkz_panel_archive_ok() {
  local a="$1"
  [ -s "$a" ] || return 1
  gzip -t "$a" 2>/dev/null || return 1
  tar -tzf "$a" 2>/dev/null | grep -qE '(^|/)artisan$' || return 1
  tar -tzf "$a" 2>/dev/null | grep -q 'resources/views/layouts/admin.blade.php' || return 1
}

hkz_panel_extract_root() {
  local extract="$1" d
  [ -f "${extract}/artisan" ] && { printf '%s' "$extract"; return 0; }
  for d in "$extract"/*; do
    [ -d "$d" ] || continue
    [ -f "${d}/artisan" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

hkz_panel_extract_tgz() {
  local tgz="$1" dest="$2" extract tmp_root
  hkz_panel_archive_ok "$tgz" || return 1
  [ -n "$dest" ] || return 1
  extract=$(mktemp -d)
  tar -xzf "$tgz" -C "$extract" || { rm -rf "$extract"; return 1; }
  tmp_root=$(hkz_panel_extract_root "$extract" 2>/dev/null || true)
  if [ -z "$tmp_root" ]; then
    rm -rf "$extract"
    return 1
  fi
  mkdir -p "$dest"
  cp -a "${tmp_root}/." "$dest/"
  rm -rf "$extract"
  return 0
}

hkz_panel_detect_version() {
  local panel="${PANEL_DIR:-/var/www/pterodactyl}" f ver
  for f in \
    "${panel}/.version" \
    "${panel}/storage/app/version" \
    "${panel}/bootstrap/cache/version"; do
    [ -f "$f" ] || continue
    ver=$(tr -d '[:space:]' <"$f" 2>/dev/null)
    ver=${ver#v}
    [ -n "$ver" ] && { printf '%s' "$ver"; return 0; }
  done
  if [ -f "${panel}/composer.lock" ]; then
    ver=$(grep -m1 '"version":' "${panel}/composer.lock" 2>/dev/null | sed -E 's/.*"version": "([^"]+)".*/\1/')
    ver=${ver#v}
    [ -n "$ver" ] && { printf '%s' "$ver"; return 0; }
  fi
  if [ -f "${panel}/artisan" ]; then
    ver=$(cd "$panel" && php artisan p:info 2>/dev/null | sed -n 's/.*Panel Version: *//p' | head -1 | tr -d '[:space:]')
    ver=${ver#v}
    [ -n "$ver" ] && { printf '%s' "$ver"; return 0; }
  fi
  return 1
}

hkz_download() {
  local url="$1" dest="$2" label="${3:-$(hkz_t dl_file)}"
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
    msg_err "$(hkz_t sync_need_curl)"
    return 1
  }
  [ -n "$url" ] || { msg_err "$(hkz_t err_url_empty) ${label}"; return 1; }
  msg_info "$(hkz_t dl_start) ${label}"
  log "DOWNLOAD: $url -> $dest"
  if ! hkz_fetch_url "$url" "$dest"; then
    msg_err "$(hkz_t dl_fail) ${label}"
    return 1
  fi
  msg_ok "$(hkz_t dl_ok) ${label}"
  return 0
}

gen_passwd() {
  local length=$1 password=""
  while [ ${#password} -lt "$length" ]; do
    password=$(head -c 200 /dev/urandom | LC_ALL=C tr -dc "$password_charset" | fold -w "$length" | head -n 1)
  done
  echo "$password"
}

valid_email() { [[ $1 =~ ${email_regex} ]]; }

invalid_ip() {
  ip route get "$1" >/dev/null 2>&1
  echo $?
}

hkz_fqdn_is_ip() {
  local h="$1"
  [[ "$h" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || [ "$h" = localhost ]
}

get_machine_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
  fi
  [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$ip" ] && command -v ip >/dev/null 2>&1 && \
    ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
  echo "$ip"
}

hkz_detect_timezone() {
  timezone=$(echo "${timezone:-}" | tr -d '[:space:]')
  if [ -n "$timezone" ]; then
    export timezone
    return 0
  fi
  local tz=""
  if command -v timedatectl >/dev/null 2>&1; then
    tz=$(timedatectl show -p Timezone --value 2>/dev/null | tr -d '[:space:]')
  fi
  if [ -z "$tz" ] && [ -f /etc/timezone ]; then
    tz=$(tr -d '[:space:]' </etc/timezone)
  fi
  if [ -z "$tz" ] && [ -e /etc/localtime ]; then
    tz=$(readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
  fi
  if [ -z "$tz" ] && command -v date >/dev/null 2>&1; then
    tz=$(date +%Z 2>/dev/null)
    [ "$tz" = "UTC" ] || [ "$tz" = "GMT" ] && tz="UTC"
  fi
  [ -z "$tz" ] && tz="UTC"
  timezone="$tz"
  export timezone
}

hkz_fetch_remote_version() {
  local b64
  command -v curl >/dev/null 2>&1 || return 1
  b64=$(curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${HKZ_INSTALLER_REPO}/contents/VERSION?ref=${HKZ_INSTALLER_BRANCH}" 2>/dev/null \
    | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -d '\n')
  [ -n "$b64" ] && echo "$b64" | base64 -d 2>/dev/null | tr -d '[:space:]'
}

hkz_installer_outdated() {
  local dir="${HKZ_INSTALL_DIR:-$HKZ_OPT_DIR}"
  local lr lv rv
  [ ! -f "${dir}/install.sh" ] && return 0
  [ ! -f "${dir}/run.sh" ] && return 0
  [ ! -x /usr/local/bin/phkz ] && return 0
  [ ! -f "${dir}/VERSION" ] && return 0
  lr=""
  [ -f "${dir}/INSTALLER_REV" ] && lr=$(tr -d '[:space:]' <"${dir}/INSTALLER_REV")
  [ "$lr" != "$HKZ_INSTALLER_REV" ] && return 0
  rv=$(hkz_fetch_remote_version)
  [ -z "$rv" ] && return 1
  lv=$(tr -d '[:space:]' <"${dir}/VERSION")
  [ "$lv" != "$rv" ] && return 0
  return 1
}

hkz_download_installer() {
  command -v curl >/dev/null 2>&1 || { echo "$(hkz_t sync_need_curl)"; return 1; }
  rm -rf /opt/PterodactylHKZAutoInstaller 2>/dev/null || true
  local api="https://api.github.com/repos/${HKZ_INSTALLER_REPO}"
  local tmp auth
  GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  [ -z "$GITHUB_TOKEN" ] && [ -f /root/.phkz_github_token ] && GITHUB_TOKEN=$(tr -d '[:space:]' </root/.phkz_github_token)
  tmp=$(mktemp -d)
  auth=(-H "Accept: application/vnd.github+json")
  [ -n "$GITHUB_TOKEN" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")
  curl -fsSL "${auth[@]}" "${api}/tarball/${HKZ_INSTALLER_BRANCH}" -o "${tmp}/repo.tar.gz" || return 1
  tar -xzf "${tmp}/repo.tar.gz" -C "${tmp}"
  local src
  src=$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -1)
  mkdir -p "$HKZ_INSTALL_DIR"
  rm -rf "${HKZ_INSTALL_DIR:?}"/*
  cp -a "${src}/." "${HKZ_INSTALL_DIR}/"
  chmod +x "${HKZ_INSTALL_DIR}/install.sh" "${HKZ_INSTALL_DIR}/run.sh" "${HKZ_INSTALL_DIR}/i.sh" \
    "${HKZ_INSTALL_DIR}/installers/"*.sh 2>/dev/null || true
  sed -i 's/\r$//' "${HKZ_INSTALL_DIR}/install.sh" "${HKZ_INSTALL_DIR}/run.sh" "${HKZ_INSTALL_DIR}/i.sh" 2>/dev/null || true
  rm -rf "${tmp}"
  hkz_install_phkz_cli
  return 0
}

hkz_install_phkz_cli() {
  local dir="${HKZ_INSTALL_DIR:-$HKZ_OPT_DIR}"
  [ ! -f "${dir}/run.sh" ] && return 1
  mkdir -p /usr/local/bin
  cat > /usr/local/bin/phkz <<EOF
#!/bin/bash
export HKZ_INSTALL_DIR="${dir}"
unset HKZ_LANG HKZ_LANG_ASKED
if [ ! -f "\${HKZ_INSTALL_DIR}/run.sh" ]; then
  echo "HKZPterodactylInstaller: \${HKZ_INSTALL_DIR}"
  echo "curl -fsSL -o /tmp/run.sh https://raw.githubusercontent.com/hakyzmain/HKZPterodactylInstaller/main/run.sh"
  echo "sudo bash /tmp/run.sh"
  exit 1
fi
exec bash "\${HKZ_INSTALL_DIR}/run.sh" "\$@"
EOF
  chmod +x /usr/local/bin/phkz
  return 0
}

hkz_ensure_opt_installer() {
  [ -n "${HKZ_INSTALLER_SYNCED:-}" ] && return 0
  hkz_installer_outdated || return 0
  local lv rv
  lv=""
  [ -f "${HKZ_INSTALL_DIR}/VERSION" ] && lv=$(tr -d '[:space:]' <"${HKZ_INSTALL_DIR}/VERSION")
  rv=$(hkz_fetch_remote_version)
  if [ -z "$lv" ]; then
    echo "> $(hkz_t sync_first) ${HKZ_INSTALL_DIR} (v${rv:-?})"
  else
    echo "> $(hkz_t sync_update) ${HKZ_INSTALL_DIR} (v${lv} → v${rv:-?})"
  fi
  hkz_download_installer || {
    msg_err "$(hkz_t err_update_fail) ${HKZ_INSTALL_DIR}"
    exit 1
  }
  export HKZ_INSTALLER_SYNCED=1
  exec env HKZ_LANG="${HKZ_LANG:-ru}" HKZ_LANG_ASKED=1 bash "${HKZ_INSTALL_DIR}/install.sh" "$@"
}

hkz_resolve_fqdn() {
  if [ -z "$FQDN" ]; then
    FQDN=$(get_machine_ip)
    [ -z "$FQDN" ] && msg_err "$(hkz_t err_no_ip)" && exit 1
    msg_info "$(hkz_t err_domain_http) ${FQDN}"
  fi
  if hkz_fqdn_is_ip "$FQDN"; then
    CONFIGURE_LETSENCRYPT=false
    ASSUME_SSL=false
  fi
  export FQDN CONFIGURE_LETSENCRYPT ASSUME_SSL
}

hkz_set_var() {
  printf -v "$1" '%s' "$2"
  export "$1"
}

required_input() {
  local __resultvar=$1 result=''
  while [ -z "$result" ]; do
    echo -en "  ${2}: "
    read -r result
    [ -z "$result" ] && [ -n "${4:-}" ] && result="$4"
    [ -z "$result" ] && msg_err "${3:-$(hkz_t input_required)}" && continue
  done
  hkz_set_var "$__resultvar" "$result"
}

email_input() {
  local __resultvar=$1 result=''
  while ! valid_email "$result"; do
    echo -en "  ${2}: "
    read -r result
    valid_email "$result" || msg_err "${3}"
  done
  hkz_set_var "$__resultvar" "$result"
}

password_input() {
  local __resultvar=$1 result='' default="${4:-}" use_default_on_empty="${5:-0}"
  while [ -z "$result" ]; do
    echo -en "  ${2}: "
    result=''
    if IFS= read -rs result </dev/tty 2>/dev/null; then
      :
    elif IFS= read -rs result; then
      :
    fi
    printf '\n'
    if [ -z "$result" ] && [ -n "$default" ]; then
      result="$default"
      [ "$use_default_on_empty" = 1 ] && msg_info "$(hkz_t ui_mysql_random_used)"
    fi
    [ -z "$result" ] && msg_err "${3}"
  done
  hkz_set_var "$__resultvar" "$result"
}

hkz_panel_clear_install_secrets() {
  rm -f "${HKZ_STAMP_DIR}/panel-install.env"
}

hkz_panel_save_install_secrets() {
  local f="${HKZ_STAMP_DIR}/panel-install.env"
  mkdir -p "$HKZ_STAMP_DIR"
  umask 077
  {
    printf 'MYSQL_PASSWORD=%q\n' "${MYSQL_PASSWORD:-}"
    printf 'MYSQL_USER=%q\n' "${MYSQL_USER:-pterodactyl}"
    printf 'MYSQL_DB=%q\n' "${MYSQL_DB:-panel}"
    printf 'user_password=%q\n' "${user_password:-}"
    printf 'user_email=%q\n' "${user_email:-}"
    printf 'user_username=%q\n' "${user_username:-admin}"
    printf 'user_firstname=%q\n' "${user_firstname:-Admin}"
    printf 'user_lastname=%q\n' "${user_lastname:-User}"
    printf 'email=%q\n' "${email:-}"
    printf 'FQDN=%q\n' "${FQDN:-}"
    printf 'timezone=%q\n' "${timezone:-}"
    printf 'ASSUME_SSL=%q\n' "${ASSUME_SSL:-false}"
    printf 'CONFIGURE_LETSENCRYPT=%q\n' "${CONFIGURE_LETSENCRYPT:-false}"
    printf 'CONFIGURE_FIREWALL=%q\n' "${CONFIGURE_FIREWALL:-false}"
    printf 'PANEL_LOCALE=%q\n' "${PANEL_LOCALE:-ru}"
    printf 'ADMIN_SKIPPED=%q\n' "${ADMIN_SKIPPED:-0}"
  } >"$f"
  chmod 600 "$f"
}

hkz_panel_print_credentials() {
  local url secrets="${HKZ_STAMP_DIR}/panel-install.env"
  hkz_panel_load_install_secrets 2>/dev/null || true
  url="http://${FQDN:-localhost}"
  if [ "${CONFIGURE_LETSENCRYPT:-false}" = true ] || [ "${ASSUME_SSL:-false}" = true ] \
    || [ -f "/etc/letsencrypt/live/${FQDN}/fullchain.pem" ]; then
    url="https://${FQDN:-localhost}"
  fi
  print_rule
  msg_ok "$(hkz_t panel_url): $url"
  msg_ok "$(hkz_t panel_login_hint)"
  msg_ok "$(hkz_t panel_admin_email): ${user_email:-?}"
  msg_ok "$(hkz_t login): ${user_username:-admin}"
  [ -n "${user_password:-}" ] \
    && msg_ok "$(hkz_t panel_admin_pass): ${user_password}" \
    || msg_warn "$(hkz_t panel_admin_pass_missing)"
  msg_info "$(hkz_t panel_creds_file): ${secrets}"
  msg_ok "$(hkz_t panel_lang): $([ "${PANEL_LOCALE:-ru}" = ru ] && hkz_t lang_ru || hkz_t lang_en)"
  msg_info "$(hkz_t panel_wings_next)"
  print_rule
}

hkz_panel_load_install_secrets() {
  local f="${HKZ_STAMP_DIR}/panel-install.env"
  [ -f "$f" ] || return 1
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
  return 0
}

hkz_mysql_bin() {
  command -v mariadb >/dev/null 2>&1 && { echo mariadb; return 0; }
  command -v mysql >/dev/null 2>&1 && { echo mysql; return 0; }
  return 1
}

hkz_mysql_cnf() {
  local cnf="$1" user="$2" pass="$3" host="${4:-}" user_q pass_q
  umask 077
  user_q=$(printf '%s' "$user" | sed 's/\\/\\\\/g; s/"/\\"/g')
  pass_q=$(printf '%s' "$pass" | sed 's/\\/\\\\/g; s/"/\\"/g')
  {
    printf '[client]\n'
    printf 'user="%s"\n' "$user_q"
    printf 'password="%s"\n' "$pass_q"
    [ -n "$host" ] && printf 'host=%s\n' "$host"
  } >"$cnf"
  chmod 600 "$cnf"
}

hkz_mysql_root_exec() {
  local sql="$1" bin errf rc
  bin=$(hkz_mysql_bin) || return 1
  errf=$(mktemp)
  if "$bin" -u root -N -B -e "$sql" >/dev/null 2>"$errf"; then
    rm -f "$errf"
    return 0
  fi
  if "$bin" -N -B -e "$sql" >/dev/null 2>"$errf"; then
    rm -f "$errf"
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo "$bin" -N -B -e "$sql" >/dev/null 2>"$errf"; then
    rm -f "$errf"
    return 0
  fi
  [ -n "${LOG_PATH:-}" ] && [ -s "$errf" ] && printf '%s\n' "$(cat "$errf")" >>"$LOG_PATH"
  rm -f "$errf"
  return 1
}

hkz_mysql_user_exec() {
  local user="$1" pass="$2" host="$3" db="$4" sql="$5"
  local bin cnf rc=1
  bin=$(hkz_mysql_bin) || return 1
  cnf=$(mktemp)
  hkz_mysql_cnf "$cnf" "$user" "$pass" "$host"
  if [ -n "$db" ]; then
    "$bin" --defaults-extra-file="$cnf" -N -B "$db" -e "$sql" >/dev/null 2>>"${LOG_PATH:-/dev/null}" && rc=0
  else
    "$bin" --defaults-extra-file="$cnf" -N -B -e "$sql" >/dev/null 2>>"${LOG_PATH:-/dev/null}" && rc=0
  fi
  rm -f "$cnf"
  return "$rc"
}

hkz_mysql_user_query() {
  local user="$1" pass="$2" host="$3" db="$4" sql="$5"
  local bin cnf out
  bin=$(hkz_mysql_bin) || return 1
  cnf=$(mktemp)
  hkz_mysql_cnf "$cnf" "$user" "$pass" "$host"
  if [ -n "$db" ]; then
    out=$("$bin" --defaults-extra-file="$cnf" -N -B "$db" -e "$sql" 2>/dev/null) || out=""
  else
    out=$("$bin" --defaults-extra-file="$cnf" -N -B -e "$sql" 2>/dev/null) || out=""
  fi
  rm -f "$cnf"
  printf '%s' "$out"
}

hkz_mysql_ping() {
  local user="$1" pass="$2" host="$3" db="$4"
  if [ -n "$db" ]; then
    hkz_mysql_user_exec "$user" "$pass" "$host" "$db" "SELECT 1;" && return 0
  fi
  hkz_mysql_user_exec "$user" "$pass" "$host" "" "SELECT 1;"
}

hkz_mysql_test_connection() {
  local user="${1:-$MYSQL_USER}" pass="${2:-$MYSQL_PASSWORD}" db="${4:-${MYSQL_DB:-panel}}" host
  [ -n "$user" ] && [ -n "$pass" ] || return 1
  for host in "${3:-}" localhost 127.0.0.1; do
    [ -z "$host" ] && continue
    if hkz_mysql_ping "$user" "$pass" "$host" "$db"; then
      MYSQL_DBHOST_HOST="$host"
      export MYSQL_DBHOST_HOST
      return 0
    fi
    log "[mysql] ping failed user=${user} host=${host} db=${db:-none}"
  done
  return 1
}

hkz_ensure_mariadb_running() {
  systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
  systemctl enable mariadb 2>/dev/null || systemctl enable mysql 2>/dev/null || true
}

hkz_resolve_php_fpm_env() {
  case "$OS" in
    ubuntu|debian)
      NGINX_AVAIL=/etc/nginx/sites-available
      NGINX_ENABL=/etc/nginx/sites-enabled
      PHP_SOCKET="${PHP_SOCKET:-/run/php/php8.3-fpm.sock}"
      ;;
    rocky|almalinux)
      NGINX_AVAIL=/etc/nginx/conf.d
      NGINX_ENABL=/etc/nginx/conf.d
      PHP_SOCKET="${PHP_SOCKET:-/var/run/php-fpm/pterodactyl.sock}"
      ;;
    *)
      return 1
      ;;
  esac
  export NGINX_AVAIL NGINX_ENABL PHP_SOCKET
}

hkz_install_php_fpm_pool() {
  local pool_dir pool_file tpl
  [ -n "${CONFIGS_DIR:-}" ] && tpl="${CONFIGS_DIR}/php-fpm-pterodactyl.conf"
  [ -f "$tpl" ] || tpl="$(dirname "${BASH_SOURCE[0]}")/../configs/php-fpm-pterodactyl.conf"
  [ -f "$tpl" ] || return 0
  for pool_dir in /etc/php-fpm.d /etc/php/8.3/fpm/pool.d; do
    [ -d "$pool_dir" ] || continue
    pool_file="${pool_dir}/pterodactyl.conf"
    sed -e "s|@WEBUSER@|${WEB_USER}|g" \
      -e "s|@WEBGROUP@|${WEB_GROUP}|g" \
      -e "s|@PHP_SOCKET@|${PHP_SOCKET}|g" "$tpl" >"$pool_file"
    return 0
  done
  return 0
}

hkz_detect_php_socket() {
  local s
  for s in \
    "${PHP_SOCKET:-}" \
    /run/php/php8.3-fpm.sock \
    /var/run/php/php8.3-fpm.sock \
    /run/php-fpm/pterodactyl.sock \
    /var/run/php-fpm/pterodactyl.sock \
    /run/php-fpm/www.sock \
    /var/run/php-fpm/www.sock; do
    [ -n "$s" ] && [ -S "$s" ] || continue
    PHP_SOCKET="$s"
    export PHP_SOCKET
    return 0
  done
  return 1
}

hkz_ensure_php_fpm() {
  hkz_resolve_php_fpm_env 2>/dev/null || true
  case "$OS" in
    ubuntu|debian)
      systemctl enable php8.3-fpm 2>/dev/null || systemctl enable php-fpm 2>/dev/null || true
      systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
      ;;
    rocky|almalinux)
      hkz_install_php_fpm_pool
      systemctl enable php-fpm 2>/dev/null || true
      systemctl restart php-fpm 2>/dev/null || true
      ;;
  esac
  sleep 1
  hkz_detect_php_socket || {
    msg_err "$(hkz_t panel_php_fpm_fail)"
    return 1
  }
  msg_ok "$(hkz_t panel_php_fpm_ok): ${PHP_SOCKET}"
  return 0
}

hkz_ensure_panel_services() {
  hkz_set_web_user 2>/dev/null || true
  hkz_ensure_mariadb_running
  hkz_ensure_php_fpm || return 1
  systemctl enable nginx 2>/dev/null || true
  systemctl restart nginx 2>/dev/null || true
  systemctl enable --now pteroq 2>/dev/null || true
  systemctl restart pteroq 2>/dev/null || true
  if [ -d "${PANEL_DIR}/storage" ]; then
    chown -R "${WEB_USER}:${WEB_GROUP}" "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
    chmod -R ug+rwx "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
  fi
  return 0
}

hkz_panel_database_tables() {
  [ ! -f "${PANEL_DIR}/artisan" ] && return 1
  msg_info "$(hkz_t db_tables)"
  (
    cd "$PANEL_DIR"
    php artisan cache:table --no-interaction >/dev/null 2>>"$LOG_PATH" || true
    php artisan session:table --no-interaction >/dev/null 2>>"$LOG_PATH" || true
    php artisan queue:table --no-interaction >/dev/null 2>>"$LOG_PATH" || true
    php artisan queue:failed-table --no-interaction >/dev/null 2>>"$LOG_PATH" || true
    php artisan migrate --force --no-interaction
  ) || return 1
  return 0
}

hkz_panel_apply_database_drivers() {
  local env="${PANEL_DIR}/.env" key new_key
  [ ! -f "$env" ] && return 1
  rm -f "${PANEL_DIR}/bootstrap/cache/config.php" 2>/dev/null || true
  if declare -F hkz_panel_ensure_app_key >/dev/null 2>&1; then
    hkz_panel_ensure_app_key || return 1
  else
    key=$(grep -E '^APP_KEY=' "$env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    key=${key#base64:}
    if [ -z "$key" ] || [ "$key" = "null" ] || [ "$key" = "SomeRandomString" ] || [ "${#key}" -lt 16 ]; then
      sed -i '/^APP_KEY=/d' "$env"
      new_key=$(php -r 'echo "base64:".base64_encode(random_bytes(32));' 2>/dev/null) || return 1
      printf '%s\n' "APP_KEY=${new_key}" >>"$env"
      rm -f "${PANEL_DIR}/bootstrap/cache/config.php" 2>/dev/null || true
    fi
  fi
  hkz_panel_database_tables || return 1
  sed -i 's/^CACHE_DRIVER=.*/CACHE_DRIVER=database/' "$env"
  sed -i 's/^SESSION_DRIVER=.*/SESSION_DRIVER=database/' "$env"
  sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=database/' "$env"
  sed -i "s/^DB_HOST=.*/DB_HOST=${MYSQL_DBHOST_HOST:-localhost}/" "$env"
  grep -q '^DB_CACHE_TABLE=' "$env" 2>/dev/null || echo 'DB_CACHE_TABLE=cache' >>"$env"
  grep -q '^DB_QUEUE_TABLE=' "$env" 2>/dev/null || echo 'DB_QUEUE_TABLE=jobs' >>"$env"
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction) || true
  (cd "$PANEL_DIR" && php artisan cache:clear --no-interaction) || true
  return 0
}

hkz_panel_admin_exists() {
  local n
  n=$(hkz_mysql_user_query "$MYSQL_USER" "$MYSQL_PASSWORD" "${MYSQL_DBHOST_HOST:-localhost}" "$MYSQL_DB" \
    "SELECT COUNT(*) FROM users WHERE email='$(hkz_sql_escape "$user_email")';")
  n=${n:-0}
  [ "${n:-0}" -gt 0 ]
}

hkz_panel_mail_log() {
  local env="${PANEL_DIR}/.env"
  [ ! -f "$env" ] && return 1
  if grep -qE '^MAIL_MAILER=' "$env" 2>/dev/null; then
    sed -i 's/^MAIL_MAILER=.*/MAIL_MAILER=log/' "$env"
  elif grep -qE '^MAIL_DRIVER=' "$env" 2>/dev/null; then
    sed -i 's/^MAIL_DRIVER=.*/MAIL_DRIVER=log/' "$env"
  else
    printf '\nMAIL_MAILER=log\n' >>"$env"
  fi
  grep -qE '^MAIL_HOST=' "$env" 2>/dev/null && sed -i 's/^MAIL_HOST=.*/MAIL_HOST=127.0.0.1/' "$env" || true
  grep -qE '^MAIL_PORT=' "$env" 2>/dev/null && sed -i 's/^MAIL_PORT=.*/MAIL_PORT=2525/' "$env" || true
  if [ -f "${PANEL_DIR}/artisan" ]; then
    (cd "$PANEL_DIR" && php artisan config:clear --no-interaction 2>/dev/null) || true
  fi
  return 0
}

hkz_export_panel_env() {
  export FQDN MYSQL_DB MYSQL_USER MYSQL_PASSWORD timezone email
  export user_email user_username user_firstname user_lastname user_password
  export ASSUME_SSL CONFIGURE_LETSENCRYPT CONFIGURE_FIREWALL INSTALL_HKZ_THEME PANEL_LOCALE
  export PANEL_DIR PANEL_DL_URL WEB_USER WEB_GROUP PHP_SOCKET NGINX_AVAIL NGINX_ENABL ADMIN_SKIPPED
}

hkz_panel_prepare_fresh_database() {
  hkz_panel_external_install && return 0
  msg_info "$(hkz_t panel_db_fresh)"
  hkz_mysql_root_exec "DROP DATABASE IF EXISTS \`${MYSQL_DB}\`;" || return 1
  return 0
}

hkz_run_panel_installer() {
  hkz_panel_clear_install_secrets
  hkz_export_panel_env
  hkz_run_installer "$1"
}

hkz_export_wings_env() {
  export WINGS_FQDN WINGS_EMAIL WINGS_CONFIGURE_SSL WINGS_CONFIGURE_FIREWALL WINGS_DBHOST
  export MYSQL_DBHOST_USER MYSQL_DBHOST_PASSWORD MYSQL_DBHOST_HOST WINGS_DEPLOY_CMD INSTALL_MARIADB
}

hkz_wings_save_env() {
  local f="${HKZ_STAMP_DIR}/wings-install.env"
  hkz_export_wings_env
  mkdir -p "$HKZ_STAMP_DIR"
  umask 077
  {
    printf 'WINGS_FQDN=%q\n' "${WINGS_FQDN:-}"
    printf 'WINGS_EMAIL=%q\n' "${WINGS_EMAIL:-}"
    printf 'WINGS_CONFIGURE_SSL=%q\n' "${WINGS_CONFIGURE_SSL:-false}"
    printf 'WINGS_CONFIGURE_FIREWALL=%q\n' "${WINGS_CONFIGURE_FIREWALL:-false}"
    printf 'WINGS_DBHOST=%q\n' "${WINGS_DBHOST:-false}"
    printf 'WINGS_DEPLOY_CMD=%q\n' "${WINGS_DEPLOY_CMD:-}"
    printf 'MYSQL_DBHOST_USER=%q\n' "${MYSQL_DBHOST_USER:-pterodactyluser}"
    printf 'MYSQL_DBHOST_PASSWORD=%q\n' "${MYSQL_DBHOST_PASSWORD:-}"
    printf 'MYSQL_DBHOST_HOST=%q\n' "${MYSQL_DBHOST_HOST:-127.0.0.1}"
    printf 'INSTALL_MARIADB=%q\n' "${INSTALL_MARIADB:-false}"
  } >"$f"
}

hkz_wings_load_env() {
  local f="${HKZ_STAMP_DIR}/wings-install.env"
  [ -f "$f" ] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$f"
  set +a
  hkz_export_wings_env
}

hkz_run_wings_installer() {
  local script="$1" rc opt="${HKZ_INSTALL_DIR:-$HKZ_OPT_DIR}"
  hkz_wings_save_env
  set -o pipefail
  env \
    HKZ_LANG="${HKZ_LANG:-ru}" \
    HKZ_INSTALL_DIR="${opt}" \
    WINGS_FQDN="${WINGS_FQDN:-}" \
    WINGS_EMAIL="${WINGS_EMAIL:-}" \
    WINGS_CONFIGURE_SSL="${WINGS_CONFIGURE_SSL:-false}" \
    WINGS_CONFIGURE_FIREWALL="${WINGS_CONFIGURE_FIREWALL:-false}" \
    WINGS_DBHOST="${WINGS_DBHOST:-false}" \
    WINGS_DEPLOY_CMD="${WINGS_DEPLOY_CMD:-}" \
    MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pterodactyluser}" \
    MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}" \
    MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}" \
    INSTALL_MARIADB="${INSTALL_MARIADB:-false}" \
    CONFIGS_DIR="${opt}/configs" \
    EMAIL="${WINGS_EMAIL:-${EMAIL:-}}" \
    bash "$script" 2>&1 | tee -a "$LOG_PATH"
  rc=${PIPESTATUS[0]}
  set +o pipefail
  return "$rc"
}

hkz_run_installer() {
  local script="$1" rc
  set -o pipefail
  env \
    HKZ_LANG="${HKZ_LANG:-ru}" \
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-}" \
    MYSQL_USER="${MYSQL_USER:-}" \
    MYSQL_DB="${MYSQL_DB:-}" \
    MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-}" \
    user_password="${user_password:-}" \
    user_email="${user_email:-}" \
    user_username="${user_username:-}" \
    user_firstname="${user_firstname:-}" \
    user_lastname="${user_lastname:-}" \
    email="${email:-}" \
    FQDN="${FQDN:-}" \
    timezone="${timezone:-}" \
    ASSUME_SSL="${ASSUME_SSL:-}" \
    CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-}" \
    CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-}" \
    PANEL_LOCALE="${PANEL_LOCALE:-}" \
    PANEL_DIR="${PANEL_DIR:-}" \
    CONFIGS_DIR="${CONFIGS_DIR:-}" \
    ADMIN_SKIPPED="${ADMIN_SKIPPED:-0}" \
    bash "$script" 2>&1 | tee -a "$LOG_PATH"
  rc=${PIPESTATUS[0]}
  set +o pipefail
  return "$rc"
}

hkz_run_theme_installer() {
  local script="$1" rc
  set -o pipefail
  env \
    HKZ_LANG="${HKZ_LANG:-ru}" \
    HKZ_INSTALL_DIR="${HKZ_INSTALL_DIR:-$HKZ_OPT_DIR}" \
    HKZ_THEME_CMD="${HKZ_THEME_CMD}" \
    HKZ_THEME_ID="${HKZ_THEME_ID}" \
    HKZ_THEME_VERBOSE="${HKZ_THEME_VERBOSE:-1}" \
    HKZ_THEME_FORCE=1 \
    HKZ_THEME_REBUILD="${HKZ_THEME_REBUILD:-1}" \
    PANEL_DIR="${PANEL_DIR}" \
    bash "$script" 2>&1 | tee -a "$LOG_PATH"
  rc=${PIPESTATUS[0]}
  set +o pipefail
  return "$rc"
}

load_config_file() {
  local cfg="${1:-$SCRIPT_DIR/install.conf}"
  if [ -f "$cfg" ]; then
    msg_info "$(hkz_t load_config) $cfg"
    set -a && source "$cfg" && set +a
  fi
}

hkz_sql_escape() {
  printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/''/g"
}

create_db_user() {
  local user="$1" pass="$2" host pass_esc
  pass_esc=$(hkz_sql_escape "$pass")
  hkz_ensure_mariadb_running
  hkz_mysql_root_exec "SELECT 1;" || {
    msg_err "$(hkz_t panel_mysql_root_fail)"
    return 1
  }
  for host in localhost 127.0.0.1; do
    hkz_mysql_root_exec "DROP USER IF EXISTS '${user}'@'${host}';" || true
    hkz_mysql_root_exec "CREATE USER '${user}'@'${host}' IDENTIFIED BY '${pass_esc}';" || return 1
  done
  hkz_mysql_root_exec "FLUSH PRIVILEGES;" || return 1
  return 0
}

create_db() {
  local db="$1" user="$2" host
  hkz_mysql_root_exec "CREATE DATABASE IF NOT EXISTS \`${db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
  for host in localhost 127.0.0.1; do
    hkz_mysql_root_exec "GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${user}'@'${host}';" || return 1
  done
  hkz_mysql_root_exec "FLUSH PRIVILEGES;" || return 1
  return 0
}

grant_db_all() {
  hkz_mysql_root_exec "GRANT ALL PRIVILEGES ON *.* TO '$2'@'${3:-127.0.0.1}' WITH GRANT OPTION;"
  hkz_mysql_root_exec "FLUSH PRIVILEGES;"
}

firewall_allow_ports() {
  case "$OS" in
    ubuntu|debian)
      for p in $1; do
        case "$p" in
          */*) ufw allow "$p" ;;
          *) ufw allow "${p}/tcp" ;;
        esac
      done
      ufw reload 2>/dev/null || true
      ;;
    rocky|almalinux)
      for p in $1; do firewall-cmd --permanent --add-port="${p}/tcp" 2>/dev/null; done
      firewall-cmd --reload 2>/dev/null || true
      ;;
  esac
}

install_firewall() {
  case "$OS" in
    ubuntu|debian)
      install_packages ufw
      ufw --force enable
      ;;
    rocky|almalinux)
      install_packages firewalld
      systemctl enable --now firewalld
      ;;
  esac
}

hkz_apt_prefer_ipv4() {
  mkdir -p /etc/apt/apt.conf.d
  printf '%s\n' 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99hkz-force-ipv4
}

hkz_apt_sanitize_stale_docker_repo() {
  case "${OS:-}" in
    ubuntu|debian) ;;
    *) return 0 ;;
  esac
  local stale=false
  [ -f /etc/apt/sources.list.d/docker.list ] && stale=true
  [ -f /etc/apt/keyrings/docker.gpg ] && stale=true
  if [ -f /etc/apt/sources.list.d/docker.sources ] && [ ! -s /etc/apt/keyrings/docker.asc ]; then
    stale=true
  fi
  $stale || return 0
  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources
  rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
}

hkz_docker_apt_repo() {
  local distro="${1:-${OS:-}}"
  [ -n "$distro" ] || detect_os
  case "$distro" in
    ubuntu|debian) ;;
    *) msg_err "docker apt: unsupported OS ${distro}"; return 1 ;;
  esac
  hkz_apt_prefer_ipv4
  hkz_apt_sanitize_stale_docker_repo
  command -v curl >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources
  rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
  curl -fsSL "https://download.docker.com/linux/${distro}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  local suite="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"
  [ -n "$suite" ] || suite="$(lsb_release -cs)"
  tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${distro}
Suites: ${suite}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

update_repos() {
  case "$OS" in
    ubuntu|debian)
      hkz_apt_sanitize_stale_docker_repo
      apt-get update -y "${@}"
      ;;
    rocky|almalinux) true ;;
  esac
}

install_packages() {
  case "$OS" in
    ubuntu|debian) DEBIAN_FRONTEND=noninteractive apt-get -y install "$@" ;;
    rocky|almalinux) dnf -y install "$@" ;;
    *) msg_err "$(hkz_t err_os_packages) ${OS:-?}"; return 1 ;;
  esac
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    OS_VER=$VERSION_ID
  else
    msg_err "$(hkz_t err_os_detect)"
    exit 1
  fi
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
  CPU_ARCHITECTURE=$(uname -m)
  case "$CPU_ARCHITECTURE" in
    x86_64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) msg_err "$(hkz_t err_arch)"; exit 1 ;;
  esac
  SUPPORTED=false
  case "$OS" in
    ubuntu)
      [[ "$OS_VER_MAJOR" == "22" || "$OS_VER_MAJOR" == "24" ]] && SUPPORTED=true
      export DEBIAN_FRONTEND=noninteractive
      ;;
    debian)
      [[ "$OS_VER_MAJOR" -ge 11 && "$OS_VER_MAJOR" -le 13 ]] && SUPPORTED=true
      export DEBIAN_FRONTEND=noninteractive
      ;;
    rocky|almalinux)
      [[ "$OS_VER_MAJOR" == "8" || "$OS_VER_MAJOR" == "9" ]] && SUPPORTED=true
      ;;
  esac
  [ "$SUPPORTED" = true ] || { msg_err "$(hkz_t err_os_unsupported) $OS $OS_VER"; exit 1; }
  export OS OS_VER OS_VER_MAJOR CPU_ARCHITECTURE ARCH SUPPORTED
}

check_virt() {
  if command -v virt-what >/dev/null 2>&1; then
    local v
    v=$(virt-what 2>/dev/null | head -1)
    [ -n "$v" ] && msg_warn "$(hkz_t warn_virt) $v"
  fi
}
