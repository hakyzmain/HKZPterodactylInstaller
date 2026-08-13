#!/bin/bash

hkz_blade_remove_markers() {
  local f="$1"
  [ -f "$f" ] || return 0
  sed -i '/data-hkz-theme-begin/,/data-hkz-theme-end/d' "$f"
  sed -i '/{{-- HKZ-AURORA-THEME-BEGIN --}}/,/{{-- HKZ-AURORA-THEME-END --}}/d' "$f"
  sed -i '/<!-- HKZ-AURORA-THEME-BEGIN -->/,/<!-- HKZ-AURORA-THEME-END -->/d' "$f"
  sed -i '/data-hkz-theme-begin/d;/data-hkz-theme-end/d' "$f"
}

hkz_theme_scrub_branding() {
  local admin="${PANEL_DIR}/resources/views/layouts/admin.blade.php"
  [ -f "$admin" ] || return 0
  sed -i 's/ data-hkz-home="1"//g' "$admin"
  sed -i 's/ <!-- HKZ-AURORA-FOOTER -->//g' "$admin"
  sed -i 's/data-hkz-home="1" //g' "$admin"
}

hkz_theme_backup_blade_file() {
  local src="$1" name="$2"
  local dest="${HKZ_STAMP_DIR}/theme-backup/${name}"
  [ -f "$src" ] || return 1
  mkdir -p "${HKZ_STAMP_DIR}/theme-backup"
  cp -af "$src" "$dest"
}

hkz_theme_restore_blade_files() {
  local wrapper="${HKZ_STAMP_DIR}/theme-backup/wrapper.blade.php"
  local admin="${HKZ_STAMP_DIR}/theme-backup/admin.blade.php"
  local restored=0
  if [ -f "$wrapper" ] && [ -f "${PANEL_DIR}/resources/views/templates/wrapper.blade.php" ]; then
    cp -af "$wrapper" "${PANEL_DIR}/resources/views/templates/wrapper.blade.php"
    restored=1
  fi
  if [ -f "$admin" ] && [ -f "${PANEL_DIR}/resources/views/layouts/admin.blade.php" ]; then
    cp -af "$admin" "${PANEL_DIR}/resources/views/layouts/admin.blade.php"
    restored=1
  fi
  [ "$restored" = 1 ]
}

hkz_blade_insert_after() {
  local file="$1" pattern="$2" inject="$3"
  local tmp inserted=0

  [ -f "$file" ] || { msg_err "$(hkz_t theme_no_file) $file"; return 1; }
  [ -f "$inject" ] || { msg_err "$(hkz_t theme_no_inject) $inject"; return 1; }

  if ! hkz_blade_has_theme_marker "$file"; then
    hkz_theme_backup_blade_file "$file" "$(basename "$file")"
  fi
  hkz_blade_remove_markers "$file"
  tmp=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >>"$tmp"
    if [ "$inserted" = 0 ] && [[ "$line" == *"$pattern"* ]]; then
      cat "$inject" >>"$tmp"
      inserted=1
    fi
  done <"$file"

  if [ "$inserted" != 1 ]; then
    rm -f "$tmp"
    msg_err "$(hkz_t theme_line_missing) $file: $pattern"
    return 1
  fi
  mv "$tmp" "$file"
}

hkz_theme_resolve_panel_root() {
  local base="$1" d
  [ -f "${base}/artisan" ] && { printf '%s' "$base"; return 0; }
  for d in "$base"/*; do
    [ -d "$d" ] || continue
    [ -f "${d}/artisan" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

hkz_theme_stock_cache_ok() {
  hkz_panel_archive_ok "$1"
}

hkz_panel_stock_urls() {
  local ver tag urls=()
  [ -n "${PANEL_DL_URL:-}" ] && urls+=("$PANEL_DL_URL")
  urls+=("https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz")
  tag=$(get_latest_release pterodactyl/panel 2>/dev/null || true)
  tag=${tag#v}
  [ -n "$tag" ] && urls+=("https://github.com/pterodactyl/panel/releases/download/v${tag}/panel.tar.gz")
  ver=$(hkz_panel_detect_version 2>/dev/null || true)
  ver=${ver#v}
  if [ -n "$ver" ] && [ "$ver" != "$tag" ]; then
    urls+=("https://github.com/pterodactyl/panel/releases/download/v${ver}/panel.tar.gz")
    urls+=("https://codeload.github.com/pterodactyl/panel/tar.gz/v${ver}")
  fi
  urls+=("https://mirror.ghproxy.com/https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz")
  [ -n "$tag" ] && urls+=("https://mirror.ghproxy.com/https://github.com/pterodactyl/panel/releases/download/v${tag}/panel.tar.gz")
  printf '%s\n' "${urls[@]}" | awk '!seen[$0]++'
}

hkz_download_panel_stock() {
  local dest="$1" start="${2:-0}" urls=() url i n total
  while IFS= read -r url; do
    [ -n "$url" ] && urls+=("$url")
  done < <(hkz_panel_stock_urls)
  n=${#urls[@]}
  [ "$n" -gt 0 ] || return 1
  total=$n
  for ((i = start; i < n; i++)); do
    url="${urls[$i]}"
    log "[theme] stock download $((i + 1))/${total}: $url"
    rm -f "$dest" 2>/dev/null || true
    if hkz_fetch_url "$url" "$dest" && hkz_theme_stock_cache_ok "$dest"; then
      log "[theme] stock download ok: $url"
      return 0
    fi
    rm -f "$dest" 2>/dev/null || true
    log "[theme] stock download failed: $url"
  done
  return 1
}

hkz_theme_extract_stock_cache() {
  local cache="$1" extract="$2" root
  rm -rf "$extract"
  mkdir -p "$extract"
  tar -xzf "$cache" -C "$extract" 2>>"${LOG_PATH:-/dev/null}" || return 1
  root=$(hkz_theme_resolve_panel_root "$extract") || return 1
  printf '%s' "$root"
}

hkz_theme_fetch_stock_root() {
  local cache="${HKZ_STAMP_DIR}/panel-stock-cache.tar.gz"
  local extract="${HKZ_STAMP_DIR}/panel-stock-extract"
  local root start="${HKZ_STOCK_DL_ATTEMPT:-0}"
  mkdir -p "$HKZ_STAMP_DIR"
  root=$(hkz_theme_resolve_panel_root "$extract" 2>/dev/null) || root=""
  if [ -n "$root" ]; then
    printf '%s' "$root"
    return 0
  fi
  if hkz_theme_stock_cache_ok "$cache"; then
    root=$(hkz_theme_extract_stock_cache "$cache" "$extract" 2>/dev/null) || root=""
    if [ -n "$root" ]; then
      printf '%s' "$root"
      return 0
    fi
    msg_warn "$(hkz_t theme_stock_cache_bad)"
    rm -f "$cache"
  fi
  msg_info "$(hkz_t theme_stock_dl)"
  hkz_download_panel_stock "$cache" "$start" || return 1
  root=$(hkz_theme_extract_stock_cache "$cache" "$extract") || {
    rm -f "$cache"
    return 1
  }
  printf '%s' "$root"
  return 0
}

hkz_theme_restore_stock_php() {
  local root="$1" f rel
  [ -n "$root" ] || return 0
  while IFS= read -r -d '' f; do
    grep -q 'nullable|current_password:admin' "$f" 2>/dev/null || continue
    rel="${f#${PANEL_DIR}/}"
    [ -f "${root}/${rel}" ] || continue
    cp -af "${root}/${rel}" "$f"
  done < <(find "${PANEL_DIR}/app" -type f -name '*.php' -print0 2>/dev/null)
}

hkz_theme_restore_stock_file() {
  local root="$1" rel="$2"
  [ -f "${root}/${rel}" ] || return 1
  mkdir -p "${PANEL_DIR}/$(dirname "$rel")"
  cp -af "${root}/${rel}" "${PANEL_DIR}/${rel}"
}

hkz_theme_remove_hkz_public() {
  rm -rf "${PANEL_DIR}/public/assets/hkz" 2>/dev/null || true
  rm -f \
    "${PANEL_DIR}/public/assets/hkz/client.css" \
    "${PANEL_DIR}/public/assets/hkz/admin.css" \
    "${PANEL_DIR}/public/assets/hkz/hkz-brand.js" \
    "${PANEL_DIR}/public/assets/hkz/hkz-console.js" \
    "${PANEL_DIR}/public/assets/hkz/hkz-admin.js" 2>/dev/null || true
}

hkz_theme_restore_stock_views() {
  local root rel dest restored=0
  root=$(hkz_theme_fetch_stock_root) || return 1
  for rel in resources/views/templates resources/views/layouts; do
    [ -d "${root}/${rel}" ] || continue
    mkdir -p "${PANEL_DIR}/resources/views"
    rm -rf "${PANEL_DIR}/${rel}"
    cp -a "${root}/${rel}" "${PANEL_DIR}/resources/views/"
    restored=1
  done
  [ "$restored" = 1 ] || return 1
  hkz_theme_restore_stock_file "$root" "resources/views/layouts/admin.blade.php" || true
  hkz_theme_restore_stock_file "$root" "resources/views/templates/wrapper.blade.php" || true
  for rel in resources/lang/en/strings.php; do
    [ -f "${root}/${rel}" ] || continue
    dest="${PANEL_DIR}/${rel}"
    mkdir -p "$(dirname "$dest")"
    cp -af "${root}/${rel}" "$dest"
  done
  if [ -f "${root}/resources/lang/ru/strings.php" ]; then
    mkdir -p "${PANEL_DIR}/resources/lang/ru"
    cp -af "${root}/resources/lang/ru/strings.php" "${PANEL_DIR}/resources/lang/ru/strings.php"
  fi
  hkz_theme_remove_hkz_public
  for rel in public/assets public/themes public/js public/favicons; do
    [ -e "${root}/${rel}" ] || continue
    rm -rf "${PANEL_DIR}/${rel}"
    cp -a "${root}/${rel}" "${PANEL_DIR}/public/"
  done
  hkz_theme_restore_stock_php "$root"
  hkz_theme_scrub_branding
  return 0
}

hkz_theme_force_clean() {
  local wrapper="${PANEL_DIR}/resources/views/templates/wrapper.blade.php"
  local admin="${PANEL_DIR}/resources/views/layouts/admin.blade.php"
  hkz_theme_remove_hkz_public
  [ -f "$wrapper" ] && hkz_blade_remove_markers "$wrapper"
  [ -f "$admin" ] && hkz_blade_remove_markers "$admin"
  hkz_theme_scrub_branding
}

hkz_theme_read_active_id() {
  tr -d '[:space:]' <"$HKZ_STAMP_THEME" 2>/dev/null || true
}

hkz_theme_client_css_broken() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -q 'pointer-events: none !important' "$f" 2>/dev/null && return 1
  return 0
}

hkz_theme_rebuild_active() {
  local id script
  id=$(hkz_theme_read_active_id 2>/dev/null || true)
  [ -n "$id" ] || return 1
  script="${HKZ_INSTALL_DIR:-${HKZ_OPT_DIR:-/opt/HKZPterodactylInstaller}}/installers/theme.sh"
  [ -f "$script" ] || return 1
  export HKZ_THEME_CMD=full HKZ_THEME_ID="$id" HKZ_THEME_REBUILD=1
  hkz_run_theme_installer "$script"
}

hkz_theme_admin_needs_repair() {
  local admin="${PANEL_DIR}/resources/views/layouts/admin.blade.php"
  local wrapper="${PANEL_DIR}/resources/views/templates/wrapper.blade.php"
  local client="${PANEL_DIR}/public/assets/hkz/active/client.css"
  local admin_css="${PANEL_DIR}/public/assets/hkz/active/admin.css"
  local id

  id=$(hkz_theme_read_active_id 2>/dev/null || true)
  if [ -n "$id" ] && [ -f "$client" ] && hkz_theme_client_css_broken "$client"; then
    return 0
  fi
  if hkz_blade_has_theme_marker "$wrapper" 2>/dev/null && [ ! -f "$client" ]; then
    return 0
  fi
  if hkz_blade_has_theme_marker "$admin" 2>/dev/null && [ ! -f "$admin_css" ]; then
    return 0
  fi
  if [ -z "$id" ] && hkz_theme_has_hkz_residuals 2>/dev/null; then
    if ! hkz_blade_has_theme_marker "$wrapper" 2>/dev/null || ! hkz_blade_has_theme_marker "$admin" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

hkz_theme_repair_admin_ui() {
  local root id theme_root
  id=$(hkz_theme_read_active_id 2>/dev/null || true)
  theme_root="${HKZ_INSTALL_DIR:-${HKZ_OPT_DIR:-/opt/HKZPterodactylInstaller}}/theme/themes"
  if [ -n "$id" ] && [ -f "${theme_root}/${id}/client.css" ] && [ -f "${theme_root}/${id}/admin.css" ]; then
    hkz_theme_rebuild_active && return $?
  fi
  hkz_theme_force_clean
  root=$(hkz_theme_fetch_stock_root 2>/dev/null) || root=""
  if [ -n "$root" ]; then
    hkz_theme_restore_stock_file "$root" "resources/views/layouts/admin.blade.php" || true
    hkz_theme_restore_stock_file "$root" "resources/views/templates/wrapper.blade.php" || true
    hkz_theme_scrub_branding
  fi
  hkz_theme_purge_caches
  hkz_theme_restart_web
}

hkz_theme_has_hkz_residuals() {
  local wrapper="${PANEL_DIR}/resources/views/templates/wrapper.blade.php"
  local admin="${PANEL_DIR}/resources/views/layouts/admin.blade.php"
  [ -d "${PANEL_DIR}/public/assets/hkz" ] && return 0
  hkz_blade_has_theme_marker "$wrapper" 2>/dev/null && return 0
  hkz_blade_has_theme_marker "$admin" 2>/dev/null && return 0
  return 1
}

hkz_theme_purge_caches() {
  cd "$PANEL_DIR"
  rm -f bootstrap/cache/config.php bootstrap/cache/routes-v7.php bootstrap/cache/services.php 2>/dev/null || true
  rm -rf storage/framework/views/* 2>/dev/null || true
  php artisan view:clear --no-interaction 2>/dev/null || true
  php artisan config:clear --no-interaction 2>/dev/null || true
  php artisan cache:clear --no-interaction 2>/dev/null || true
  php artisan route:clear --no-interaction 2>/dev/null || true
  php artisan optimize:clear --no-interaction 2>/dev/null || true
}

hkz_theme_restart_web() {
  hkz_ensure_mariadb_running 2>/dev/null || true
  case "$OS" in
    ubuntu|debian)
      systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
      ;;
    rocky|almalinux)
      systemctl restart php-fpm 2>/dev/null || true
      ;;
  esac
  systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true
}
