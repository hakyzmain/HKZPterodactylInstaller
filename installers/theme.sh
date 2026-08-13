#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/verify.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-customize.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/theme-blade.sh"

HKZ_THEME_CMD="${HKZ_THEME_CMD:-full}"
HKZ_THEME_ID="${HKZ_THEME_ID:-aurora}"
HKZ_THEME_VERBOSE="${HKZ_THEME_VERBOSE:-0}"
HKZ_THEME_FORCE="${HKZ_THEME_FORCE:-0}"
HKZ_THEME_REBUILD="${HKZ_THEME_REBUILD:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_ROOT="${HKZ_INSTALL_DIR:-$SCRIPT_DIR}/theme"
THEME_BASE="${THEME_ROOT}/_base"
THEME_INJECT="${THEME_ROOT}/inject"
THEMES_DIR="${THEME_ROOT}/themes"
HKZ_ACTIVE_DIR="assets/hkz/active"

hkz_theme_log() {
  log "[theme] $*"
  [ "${HKZ_THEME_VERBOSE}" = 1 ] && echo -e "  ${C_DIM}[theme]${C_RESET} $*"
}

hkz_theme_run_logged() {
  local title="$1" rc
  shift
  hkz_theme_log "=== $title ==="
  hkz_theme_log "CMD: $*"
  if [ "${HKZ_THEME_VERBOSE}" = 1 ]; then
    set -o pipefail
    "$@" 2>&1 | tee -a "$LOG_PATH"
    rc=${PIPESTATUS[0]}
    set +o pipefail
  else
    "$@" >>"$LOG_PATH" 2>&1
    rc=$?
  fi
  hkz_theme_log "exit=$rc ($title)"
  return "$rc"
}

hkz_theme_normalize_id() {
  local raw="${1:-aurora}"
  local catalog
  raw=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$raw" in
    hkz|hkztheme|hkz-aurora) echo aurora ;;
    '') echo "" ;;
    *)
      catalog="$(hkz_theme_catalog_path)"
      if [ -f "$catalog" ] && grep -qE "^${raw}\|" "$catalog" 2>/dev/null; then
        echo "$raw"
      else
        echo ""
      fi
      ;;
  esac
}

hkz_theme_catalog_path() {
  echo "${THEME_ROOT}/catalog.conf"
}

hkz_theme_display_name() {
  local id="$1"
  local line
  line=$(grep -E "^${id}\|" "$(hkz_theme_catalog_path)" 2>/dev/null | head -1)
  [ -n "$line" ] && echo "${line#*|}" || echo "$id"
}

hkz_theme_resolve_id() {
  local cmd="${HKZ_THEME_CMD:-}"
  local id="${HKZ_THEME_ID:-}"
  case "$cmd" in
    default|standard|std|remove) echo "" ;;
    full|install|hkz|"")
      hkz_theme_normalize_id "${id:-aurora}"
      ;;
    *)
      hkz_theme_normalize_id "$cmd"
      ;;
  esac
}

hkz_remove_blueprint() {
  msg_step "$(hkz_t theme_rm_blueprint)"
  rm -f /usr/local/bin/blueprint 2>/dev/null || true
  rm -f "$PANEL_DIR/blueprint.sh" "$PANEL_DIR/.blueprintrc" 2>/dev/null || true
  rm -f "$PANEL_DIR"/*.blueprint 2>/dev/null || true
  rm -rf "$PANEL_DIR/.blueprint" 2>/dev/null || true
  rm -rf "$PANEL_DIR/resources/views/blueprint" 2>/dev/null || true
}

hkz_theme_verify_id() {
  local id="$1"
  [ -n "$id" ] || return 1
  [ -f "${THEMES_DIR}/${id}/client.css" ] || return 1
  [ -f "${THEMES_DIR}/${id}/admin.css" ] || return 1
  return 0
}

hkz_theme_client_skin() {
  local f="$1"
  [ -f "$f" ] || return 1
  cat "$f"
}

hkz_theme_client_for_admin() {
  local f="$1"
  [ -f "$f" ] || return 1
  awk '
    /^html, body, #app|^html,[[:space:]]*body|^body\.bg-neutral-900[[:space:]]*\{/ { skip = 1; depth = 0 }
    /^#app::before|^#app::after|^\.wrapper::before|^\.wrapper::after/ { skip = 1; depth = 0 }
    /^h1,[[:space:]]*h2|^div\[class/ { skip = 1; depth = 0 }
    skip {
      if (/\{/) depth++
      if (/\}/) {
        depth--
        if (depth <= 0) skip = 0
      }
      next
    }
    { print }
  ' "$f"
}

hkz_theme_admin_skin() {
  local f="$1"
  [ -f "$f" ] || return 1
  awk '
    /^@import/ { print; next }
    /^:root[[:space:]]*\{/ { skip = 1; depth = 0; print; next }
    skip {
      print
      if (/\{/) depth++
      if (/\}/) {
        depth--
        if (depth <= 0) skip = 0
      }
      next
    }
    { next }
  ' "$f"
}

hkz_theme_bundle_rev() {
  local revf="${SCRIPT_DIR}/INSTALLER_REV"
  [ -f "$revf" ] && tr -d '[:space:]' <"$revf" || echo "0"
}

hkz_theme_client_css_broken() {
  local f="$1"
  [ -f "$f" ] || return 1
  awk '
    BEGIN { bad = 0 }
    /^#app::before|^#app::after|^\.wrapper::before|^\.wrapper::after/ {
      inblock = 1
      buf = ""
    }
    inblock {
      buf = buf $0 "\n"
      if ($0 ~ /\}/) {
        if (buf !~ /pointer-events:[[:space:]]*none/) bad = 1
        inblock = 0
      }
    }
    END {
      if (inblock) bad = 1
      exit bad ? 0 : 1
    }
  ' "$f"
}

hkz_theme_validate_client_css() {
  local f="$1"
  if ! grep -q 'pointer-events: none !important' "$f" 2>/dev/null; then
    msg_err "$(hkz_t theme_css_broken 2>/dev/null || echo 'broken HKZ client.css bundle (overlay blocks clicks)')"
    return 1
  fi
  return 0
}

hkz_theme_assemble_css() {
  local id="$1" kind="$2" dest="$3"
  local rev
  rev=$(hkz_theme_bundle_rev)
  if [ "$kind" = client ]; then
    {
      echo ":root{--hkz-bundle:${rev}}"
      hkz_theme_client_skin "${THEMES_DIR}/${id}/client.css"
      cat "${THEME_BASE}/polish-client.css" \
        "${THEME_BASE}/client-compat.css" \
        "${THEME_BASE}/thin-guard.css"
    } >"$dest"
  else
    {
      echo ":root{--hkz-bundle:${rev}}"
      hkz_theme_admin_skin "${THEMES_DIR}/${id}/admin.css"
      cat "${THEME_BASE}/polish-admin.css" \
        "${THEME_BASE}/admin-compat.css" \
        "${THEME_BASE}/admin-skin.css" \
        "${THEME_BASE}/thin-guard.css"
    } >"$dest"
  fi
}

hkz_theme_install_brand_js() {
  local dest dir="${PANEL_DIR}/public/assets/hkz"
  mkdir -p "$dir"
  cp -f "${THEME_INJECT}/hkz-brand.js" "${dir}/hkz-brand.js"
  chown "$WEB_USER:$WEB_GROUP" "${dir}/hkz-brand.js" 2>/dev/null || true
  rm -f "${dir}/hkz-console.js" "${dir}/hkz-admin.js" 2>/dev/null || true
}

hkz_theme_install_assets() {
  local id="$1"
  local active="${PANEL_DIR}/public/${HKZ_ACTIVE_DIR}"
  local archive="${PANEL_DIR}/public/assets/hkz/themes/${id}"

  msg_step "$(hkz_t theme_install) $(hkz_theme_display_name "$id")"
  hkz_theme_verify_id "$id" || { msg_err "$(hkz_t theme_no_id) $id"; return 1; }

  mkdir -p "$active" "$archive" "${PANEL_DIR}/public/assets/hkz/themes"
  hkz_theme_assemble_css "$id" client "${active}/client.css"
  hkz_theme_validate_client_css "${active}/client.css" || return 1
  hkz_theme_assemble_css "$id" admin "${active}/admin.css"
  cp -f "${active}/client.css" "${archive}/client.css"
  cp -f "${active}/admin.css" "${archive}/admin.css"

  rm -f "${PANEL_DIR}/public/assets/hkz/client.css" "${PANEL_DIR}/public/assets/hkz/admin.css" 2>/dev/null || true
  ln -sf "active/client.css" "${PANEL_DIR}/public/assets/hkz/client.css" 2>/dev/null \
    || cp -f "${active}/client.css" "${PANEL_DIR}/public/assets/hkz/client.css"
  ln -sf "active/admin.css" "${PANEL_DIR}/public/assets/hkz/admin.css" 2>/dev/null \
    || cp -f "${active}/admin.css" "${PANEL_DIR}/public/assets/hkz/admin.css"

  chown -R "$WEB_USER:$WEB_GROUP" "${PANEL_DIR}/public/assets/hkz"
  msg_ok "$(hkz_t theme_pub_ok) ${id}"
}

hkz_theme_patch_views() {
  local wrapper="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
  local admin="$PANEL_DIR/resources/views/layouts/admin.blade.php"

  msg_step "$(hkz_t theme_wire)"
  hkz_verify_file "$wrapper" 50 "wrapper.blade.php" || return 1
  hkz_verify_file "$admin" 50 "admin.blade.php" || return 1

  hkz_blade_insert_after "$wrapper" "@yield('assets')" "${THEME_INJECT}/client.blade.php" || return 1
  if grep -q "Theme::css('css/pterodactyl.css" "$admin"; then
    hkz_blade_insert_after "$admin" "Theme::css('css/pterodactyl.css" "${THEME_INJECT}/admin.blade.php" || return 1
  else
    hkz_blade_insert_after "$admin" "@section('scripts')" "${THEME_INJECT}/admin.blade.php" || return 1
  fi
  msg_ok "$(hkz_t theme_wrapper_ok)"
}

hkz_theme_clear_caches() {
  hkz_theme_run_logged "theme purge caches" hkz_theme_purge_caches
}

hkz_theme_diagnose() {
  local panel="${PANEL_DIR:-/var/www/pterodactyl}"
  local id
  id=$(tr -d '[:space:]' <"$HKZ_STAMP_THEME" 2>/dev/null || echo "?")
  hkz_theme_log "$(hkz_t theme_diag_start)"
  hkz_theme_log "$(hkz_t theme_diag_active) $id ($(hkz_theme_display_name "$id" 2>/dev/null || echo ?))"
  for f in \
    "$panel/public/assets/hkz/active/client.css" \
    "$panel/public/assets/hkz/active/admin.css"; do
    if [ -f "$f" ]; then
      hkz_theme_log "OK: $f ($(wc -c <"$f") bytes)"
      if [ "$f" = "$panel/public/assets/hkz/active/client.css" ] && hkz_theme_client_css_broken "$f"; then
        hkz_theme_log "WARN: broken client.css overlay — rebuild theme (phkz repair or phkz theme)"
      fi
    else
      hkz_theme_log "MISSING: $f"
    fi
  done
  hkz_theme_log "$(hkz_t theme_diag_end)"
}

hkz_theme_mark_active() {
  local id="$1"
  mkdir -p "$HKZ_STAMP_DIR"
  echo "$id" >"$HKZ_STAMP_THEME"
}

hkz_theme_unmark() {
  rm -f "$HKZ_STAMP_THEME" 2>/dev/null || true
}

install_hkz_theme() {
  local id
  id=$(hkz_theme_resolve_id)
  [ -n "$id" ] || { msg_err "$(hkz_t theme_not_set)"; return 1; }
  export HKZ_THEME_ID="$id"

  hkz_verify_file "${THEME_BASE}/thin-guard.css" 20 "thin-guard.css" || return 1
  hkz_verify_file "${THEME_BASE}/polish-client.css" 20 "polish-client.css" || return 1
  hkz_verify_file "${THEME_BASE}/polish-admin.css" 20 "polish-admin.css" || return 1
  hkz_remove_blueprint
  hkz_theme_install_assets "$id" || return 1
  hkz_theme_install_brand_js || return 1
  hkz_theme_patch_views || return 1
  if [ -n "${PANEL_LOCALE:-}" ]; then
    hkz_panel_apply_locale || msg_warn "$(hkz_t theme_locale_warn) ${LOG_PATH}"
  fi
  hkz_panel_apply_branding || msg_warn "$(hkz_t theme_brand_warn) ${LOG_PATH}"
  hkz_theme_clear_caches
  chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"
  hkz_theme_mark_active "$id"
  if ! hkz_verify_hkztheme_installed; then
    hkz_theme_diagnose
    hkz_theme_patch_views || return 1
    hkz_theme_clear_caches
    hkz_verify_hkztheme_installed || return 1
  fi
  hkz_theme_diagnose
  msg_ok "$(hkz_theme_display_name "$id") $(hkz_t theme_applied)"
}

remove_hkz_theme() {
  msg_step "$(hkz_t theme_std_install)"
  local attempt=0 stock_ok=0 cache="${HKZ_STAMP_DIR}/panel-stock-cache.tar.gz"
  rm -rf "${HKZ_STAMP_DIR}/panel-stock-extract" 2>/dev/null || true
  while [ "$attempt" -lt 3 ]; do
    export HKZ_STOCK_DL_ATTEMPT="$attempt"
    if hkz_theme_restore_stock_views; then
      stock_ok=1
      msg_ok "$(hkz_t theme_stock_ok)"
      break
    fi
    attempt=$((attempt + 1))
    rm -rf "${HKZ_STAMP_DIR}/panel-stock-extract" 2>/dev/null || true
    hkz_theme_stock_cache_ok "$cache" 2>/dev/null || rm -f "$cache" 2>/dev/null || true
    [ "$attempt" -lt 3 ] && msg_warn "$(hkz_t theme_stock_retry)"
  done
  unset HKZ_STOCK_DL_ATTEMPT 2>/dev/null || true
  if [ "$stock_ok" != 1 ]; then
    if hkz_theme_restore_blade_files; then
      msg_info "$(hkz_t theme_blade_restored)"
    else
      msg_warn "$(hkz_t theme_std_fallback)"
      msg_info "$(hkz_t theme_std_fallback_hint) ${cache}"
    fi
    hkz_panel_revert_branding 2>/dev/null || true
    hkz_theme_force_clean
  fi
  hkz_theme_remove_hkz_public
  rm -rf "${HKZ_STAMP_DIR}/theme-backup" 2>/dev/null || true
  hkz_theme_unmark
  hkz_theme_force_clean
  hkz_theme_clear_caches
  chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"
  hkz_theme_restart_web
  if hkz_theme_has_hkz_residuals; then
    hkz_theme_force_clean
    hkz_theme_clear_caches
    hkz_theme_restart_web
    msg_warn "$(hkz_t theme_std_cleanup)"
  fi
  msg_ok "$(hkz_t theme_std_ok)"
  return 0
}

hkz_theme_cmd_main() {
  [ -z "${OS:-}" ] && detect_os
  hkz_set_web_user || exit 1
  hkz_verify_panel_tree || exit 1

  hkz_theme_log "$(hkz_t theme_log_start) CMD=${HKZ_THEME_CMD:-?} ID=${HKZ_THEME_ID:-?} PANEL=${PANEL_DIR}"
  hkz_theme_log "$(hkz_t theme_log_pack) ${THEME_ROOT} (rebuild=${HKZ_THEME_REBUILD})"
  [ -f "$(hkz_theme_catalog_path)" ] || { msg_err "$(hkz_t theme_no_file) $(hkz_theme_catalog_path)"; exit 1; }

  case "$HKZ_THEME_CMD" in
    default|standard|std|remove)
      remove_hkz_theme || exit 1
      ;;
    list)
      msg_info "$(hkz_t theme_avail)"
      while IFS='|' read -r tid tname; do
        [ -z "$tid" ] || [[ "$tid" == \#* ]] && continue
        echo "  - $tid: $tname"
      done <"$(hkz_theme_catalog_path)"
      ;;
    *)
      export HKZ_THEME_FORCE=1
      install_hkz_theme || exit 1
      ;;
  esac
}

hkz_theme_cmd_main "$@"
