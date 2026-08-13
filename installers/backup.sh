#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"

BACKUP_DIR="${HKZ_BACKUP_DIR:-/var/backups/phkz-panel}"
hkz_resolve_panel_dir 2>/dev/null || true
hkz_panel_files_exist || { msg_err "$(hkz_t upd_no_panel)"; exit 1; }

msg_step "$(hkz_t upd_backup)"
mkdir -p "$BACKUP_DIR"
stamp=$(date +%Y%m%d_%H%M%S)
dest="$BACKUP_DIR/panel_$stamp"
mkdir -p "$dest"
cp -a "$PANEL_DIR/.env" "$dest/.env"
if [ -f "$PANEL_DIR/.env" ]; then
  DB_NAME=$(grep '^DB_DATABASE=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
  DB_USER=$(grep '^DB_USERNAME=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
  DB_PASS=$(grep '^DB_PASSWORD=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
  if [ -n "$DB_NAME" ]; then
    mariadb-dump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" >"$dest/database.sql" 2>/dev/null \
      || mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" >"$dest/database.sql"
  fi
fi
tar -czf "$dest/storage.tar.gz" -C "$PANEL_DIR" storage
echo "$dest" >"$BACKUP_DIR/latest.txt"
msg_ok "$dest"
