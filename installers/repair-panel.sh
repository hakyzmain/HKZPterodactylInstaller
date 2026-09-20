#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/../lib/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-customize.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-heal.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/panel-admin.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/theme-blade.sh"

CONFIGS_DIR="$(dirname "${BASH_SOURCE[0]}")/../configs"
export CONFIGS_DIR

[ -z "${OS:-}" ] && detect_os
hkz_resolve_panel_dir 2>/dev/null || true
hkz_panel_load_install_secrets 2>/dev/null || true
hkz_export_panel_env
hkz_panel_files_exist || { msg_err "$(hkz_t upd_no_panel)"; exit 1; }
hkz_set_web_user 2>/dev/null || true
if hkz_theme_admin_needs_repair 2>/dev/null; then
  if [ -n "$(hkz_theme_read_active_id 2>/dev/null || true)" ]; then
    msg_step "$(hkz_t theme_rebuild_active 2>/dev/null || echo 'Rebuilding HKZ theme CSS')"
    hkz_theme_rebuild_active || hkz_theme_repair_admin_ui || msg_warn "$(hkz_t theme_std_fallback)"
  else
    msg_step "$(hkz_t theme_std_install)"
    hkz_theme_repair_admin_ui || msg_warn "$(hkz_t theme_std_fallback)"
  fi
fi
hkz_panel_finalize
