#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/github.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-customize.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-heal.sh"

BACKUP_DIR="${HKZ_BACKUP_DIR:-/var/backups/phkz-panel}"
SKIP_BACKUP="${SKIP_BACKUP:-false}"

detect_web_user() {
  case "$OS" in
    ubuntu|debian) WEB_USER=www-data WEB_GROUP=www-data ;;
    rocky|almalinux) WEB_USER=nginx WEB_GROUP=nginx ;;
  esac
  export WEB_USER WEB_GROUP
}

backup_panel() {
  [ "$SKIP_BACKUP" = true ] && return 0
  msg_step "$(hkz_t upd_backup)"
  mkdir -p "$BACKUP_DIR"
  stamp=$(date +%Y%m%d_%H%M%S)
  dest="$BACKUP_DIR/panel_$stamp"
  mkdir -p "$dest"
  cp -a "$PANEL_DIR/.env" "$dest/.env" 2>/dev/null || true
  if [ -f "$PANEL_DIR/.env" ]; then
    DB_NAME=$(grep '^DB_DATABASE=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
    DB_USER=$(grep '^DB_USERNAME=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
    DB_PASS=$(grep '^DB_PASSWORD=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
    if [ -n "$DB_NAME" ]; then
      mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" >"$dest/database.sql" 2>/dev/null \
        || mariadb-dump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" >"$dest/database.sql"
    fi
  fi
  tar -czf "$dest/storage.tar.gz" -C "$PANEL_DIR" storage 2>/dev/null || true
  echo "$stamp" >"$BACKUP_DIR/latest.txt"
  msg_ok "$dest"
}

update_panel_files() {
  msg_step "$(hkz_t upd_panel)"
  local latest old_ver env_bak panel_tar
  latest=$(get_latest_release "pterodactyl/panel")
  old_ver=$(cd "$PANEL_DIR" && php artisan p:info 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || hkz_t ver_unknown)
  msg_info "$old_ver → $latest"
  env_bak=$(mktemp)
  panel_tar=$(mktemp)
  cd "$PANEL_DIR"
  cp .env "$env_bak"
  hkz_download "$PANEL_DL_URL" "$panel_tar" "panel.tar.gz" || { rm -f "$env_bak" "$panel_tar"; return 1; }
  hkz_panel_archive_ok "$panel_tar" || {
    msg_err "$(hkz_t panel_archive_bad)"
    rm -f "$env_bak" "$panel_tar"
    return 1
  }
  hkz_panel_extract_tgz "$panel_tar" "$PANEL_DIR" || {
    msg_err "$(hkz_t panel_archive_bad)"
    rm -f "$env_bak" "$panel_tar"
    return 1
  }
  rm -f "$panel_tar"
  mv "$env_bak" "${PANEL_DIR}/.env"
  chmod -R 755 storage/* bootstrap/cache/ 2>/dev/null || chmod -R 755 storage bootstrap/cache
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  php artisan migrate --force
  php artisan optimize:clear 2>/dev/null || true
  php artisan view:clear
  php artisan config:clear
  php artisan cache:clear
  php artisan queue:restart 2>/dev/null || true
  hkz_panel_fix_permissions 2>/dev/null || chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"
  systemctl restart pteroq
  systemctl reload nginx
  msg_ok "$latest"
}

reapply_hkz_after_update() {
  local tid
  hkz_resolve_panel_dir 2>/dev/null || true
  [ -f /var/lib/phkz/panel-locale ] && PANEL_LOCALE=$(tr -d '[:space:]' </var/lib/phkz/panel-locale)
  if hkz_hkztheme_active || [ -f "${PANEL_DIR}/public/assets/hkz/active/client.css" ] \
    || hkz_blade_has_theme_marker; then
    msg_step "$(hkz_t upd_retheme)"
    tid=$(tr -d '[:space:]' <"$HKZ_STAMP_THEME" 2>/dev/null || true)
    [ -z "$tid" ] && tid=aurora
    export HKZ_THEME_CMD="$tid" HKZ_THEME_ID="$tid" HKZ_THEME_FORCE=1 HKZ_THEME_VERBOSE=0
    env HKZ_LANG="${HKZ_LANG:-ru}" bash "$(dirname "${BASH_SOURCE[0]}")/theme.sh" || msg_warn "$(hkz_t upd_retheme_fail)"
  fi
  hkz_panel_apply_customization 2>/dev/null || true
}

panel_update_main() {
  hkz_resolve_panel_dir 2>/dev/null || true
  hkz_panel_files_exist || { msg_err "$(hkz_t upd_no_panel)"; exit 1; }
  detect_os
  detect_web_user
  backup_panel
  update_panel_files
  reapply_hkz_after_update
  hkz_panel_finalize
}

panel_update_main
