#!/bin/bash

hkz_verify_file() {
  local f="$1" min="${2:-1}" label="${3:-$(hkz_t vfy_file)}"
  [ -f "$f" ] || { msg_err "$(hkz_t vfy_no_file) $label: $f"; return 1; }
  local sz
  sz=$(wc -c <"$f" 2>/dev/null || echo 0)
  [ "$sz" -ge "$min" ] || { msg_err "$label $(hkz_t vfy_too_small) $f"; return 1; }
  return 0
}

hkz_verify_dir() {
  local d="$1" label="${2:-$(hkz_t vfy_dir)}"
  [ -d "$d" ] || { msg_err "$(hkz_t vfy_no_dir) $label: $d"; return 1; }
  return 0
}

hkz_verify_panel_tree() {
  local d="${1:-$PANEL_DIR}"
  local fail=0
  hkz_verify_file "$d/artisan" 1 "artisan" || fail=1
  hkz_verify_dir "$d/app" "app/" || fail=1
  hkz_verify_dir "$d/public" "public/" || fail=1
  hkz_verify_file "$d/public/index.php" 20 "public/index.php" || fail=1
  hkz_verify_file "$d/resources/views/layouts/admin.blade.php" 50 "admin.blade.php" || fail=1
  hkz_verify_file "$d/.env" 10 ".env" || fail=1
  [ "$fail" = 0 ] && msg_ok "$(hkz_t vfy_tree_ok)"
  return $fail
}

hkz_verify_hkztheme_installed() {
  hkz_verify_file "$PANEL_DIR/public/assets/hkz/active/client.css" 500 "client.css" || return 1
  hkz_verify_file "$PANEL_DIR/public/assets/hkz/active/admin.css" 50 "admin.css" || return 1
  hkz_blade_has_theme_marker || {
    msg_err "$(hkz_t vfy_marker_fail)"
    return 1
  }
  msg_ok "$(hkz_t vfy_theme_ok)"
}
