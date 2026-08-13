#!/bin/bash

set -e

HKZ_INSTALLER_REPO="${HKZ_INSTALLER_REPO:-hakyzmain/HKZPterodactylInstaller}"
HKZ_INSTALLER_BRANCH="${HKZ_INSTALLER_BRANCH:-main}"
HKZ_INSTALL_DIR="${HKZ_INSTALL_DIR:-}"

hkz_need_bootstrap() {
  local dir="$1"
  [ -z "$dir" ] && return 0
  [[ "$dir" == /dev/fd/* ]] && return 0
  [ ! -f "${dir}/lib/lib.sh" ] && return 0
  [ ! -f "${dir}/install.sh" ] && return 0
  grep -q 'hkz_bootstrap_token' "${dir}/install.sh" 2>/dev/null || return 0
  return 1
}

hkz_bootstrap_token() {
  GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  [ -z "$GITHUB_TOKEN" ] && [ -f /root/.phkz_github_token ] && GITHUB_TOKEN=$(tr -d '[:space:]' </root/.phkz_github_token)
  [ -z "$GITHUB_TOKEN" ] && command -v gh >/dev/null 2>&1 && GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
  export GITHUB_TOKEN
}

hkz_bootstrap() {
  command -v curl >/dev/null 2>&1 || {
    if [ "${HKZ_LANG:-ru}" = en ]; then echo "curl required"; else echo "нужен curl"; fi
    exit 1
  }
  local api="https://api.github.com/repos/${HKZ_INSTALLER_REPO}"
  local tmp auth
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  hkz_bootstrap_token
  if [ -n "$GITHUB_TOKEN" ]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")
  else
    auth=(-H "Accept: application/vnd.github+json")
  fi
  if [ "${HKZ_LANG:-ru}" = en ]; then
    echo "> downloading..."
  else
    echo "> загрузка..."
  fi
  if ! curl -fsSL "${auth[@]}" "${api}/tarball/${HKZ_INSTALLER_BRANCH}" -o "${tmp}/repo.tar.gz"; then
    if [ "${HKZ_LANG:-ru}" = en ]; then
      echo "download failed — private repo needs GITHUB_TOKEN"
    else
      echo "не удалось скачать — для приватного репо нужен GITHUB_TOKEN"
    fi
    exit 1
  fi
  tar -xzf "${tmp}/repo.tar.gz" -C "${tmp}"
  src=$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -1)
  mkdir -p "$HKZ_INSTALL_DIR"
  rm -rf "${HKZ_INSTALL_DIR:?}"/*
  cp -a "${src}/." "${HKZ_INSTALL_DIR}/"
  chmod +x "${HKZ_INSTALL_DIR}/install.sh" "${HKZ_INSTALL_DIR}/run.sh" "${HKZ_INSTALL_DIR}/i.sh" "${HKZ_INSTALL_DIR}/installers/"*.sh 2>/dev/null || true
  export HKZ_BOOTSTRAP_DONE=1 HKZ_INSTALL_DIR HKZ_INSTALLER_REPO HKZ_INSTALLER_BRANCH
  exec bash "${HKZ_INSTALL_DIR}/install.sh" "${@:-menu}"
}

hkz_pre_sync_remote_version() {
  local b64
  b64=$(curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${HKZ_INSTALLER_REPO}/contents/VERSION?ref=${HKZ_INSTALLER_BRANCH}" 2>/dev/null \
    | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -d '\n')
  [ -n "$b64" ] && echo "$b64" | base64 -d 2>/dev/null | tr -d '[:space:]'
}

hkz_pre_sync_opt() {
  [ -n "${HKZ_INSTALLER_SYNCED:-}" ] && return 0
  local dir="${HKZ_INSTALL_DIR:-/opt/HKZPterodactylInstaller}"
  local need=0 lr lv rv want
  rm -rf /opt/PterodactylHKZAutoInstaller 2>/dev/null || true
  [ ! -f "${dir}/install.sh" ] && need=1
  [ ! -f "${dir}/run.sh" ] && need=1
  [ ! -x /usr/local/bin/phkz ] && need=1
  [ ! -f "${dir}/VERSION" ] && need=1
  if [ -f "${dir}/VERSION" ]; then
    lv=$(tr -d '[:space:]' <"${dir}/VERSION")
    rv=$(hkz_pre_sync_remote_version)
    [ -n "$rv" ] && [ "$lv" != "$rv" ] && need=1
  fi
  lr=""
  [ -f "${dir}/INSTALLER_REV" ] && lr=$(tr -d '[:space:]' <"${dir}/INSTALLER_REV")
  want=""
  [ -f "${_SCRIPT_DIR}/INSTALLER_REV" ] && want=$(tr -d '[:space:]' <"${_SCRIPT_DIR}/INSTALLER_REV")
  [ -z "$want" ] && want="${HKZ_INSTALLER_REV:-112}"
  [ -n "$want" ] && [ "$lr" != "$want" ] && need=1
  [ "$need" = 1 ] && [ -f "${dir}/run.sh" ] && exec env HKZ_INSTALLER_SYNCED=1 bash "${dir}/run.sh" "$@"
}

_SCRIPT_SRC="${BASH_SOURCE[0]}"
_SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT_SRC")" 2>/dev/null && pwd)" || _SCRIPT_DIR=""

hkz_pre_sync_opt "$@"

if hkz_need_bootstrap "$_SCRIPT_DIR"; then
  hkz_bootstrap "$@"
fi

SCRIPT_DIR="${HKZ_INSTALL_DIR:-$_SCRIPT_DIR}"
[ -f "${SCRIPT_DIR}/lib/lib.sh" ] && SCRIPT_DIR="$(cd "${SCRIPT_DIR}" && pwd)"
[ -f "${_SCRIPT_DIR}/lib/lib.sh" ] && [ ! -f "${SCRIPT_DIR}/lib/lib.sh" ] && SCRIPT_DIR="$(cd "${_SCRIPT_DIR}" && pwd)"

source "$SCRIPT_DIR/lib/lib.sh"
source "$SCRIPT_DIR/lib/github.sh"

resolve_github_token
mkdir -p "$(dirname "$LOG_PATH")" "$HKZ_INSTALL_DIR"
touch "$LOG_PATH" 2>/dev/null || true
hkz_install_phkz_cli

install_cli_tool() {
  hkz_install_phkz_cli
}

setup_auto_update_cron() {
  [ "${AUTO_UPDATE_PANEL:-false}" != true ] && return 0
  echo "0 4 * * 0 root ${HKZ_INSTALL_DIR}/install.sh update --quiet >> ${LOG_PATH} 2>&1" > /etc/cron.d/phkz-panel-update
  chmod 644 /etc/cron.d/phkz-panel-update
}

cmd_install() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  if hkz_panel_files_exist && hkz_panel_core_ok 2>/dev/null; then
    draw_logo
    hkz_panel_report_detect || true
    msg_info "$(hkz_t panel_existing_ops)"
    return 0
  fi
  hkz_panel_clear_install_secrets
  source "$SCRIPT_DIR/lib/ui.sh"
  run_ui
  hkz_set_web_user || exit 1
  cp -a "$SCRIPT_DIR/." "$HKZ_INSTALL_DIR/" 2>/dev/null || true
  SCRIPT_DIR="$HKZ_INSTALL_DIR"
  hkz_export_panel_env
  hkz_run_panel_installer "$SCRIPT_DIR/installers/panel.sh" || {
    msg_err "$(hkz_t install_panel_fail) ${LOG_PATH}"
    exit 1
  }
  if [ "${INSTALL_HKZ_THEME:-false}" = true ]; then
    export HKZ_THEME_CMD=full HKZ_THEME_ID="${HKZ_THEME_ID:-aurora}" HKZ_THEME_VERBOSE=1
    hkz_run_installer "$SCRIPT_DIR/installers/theme.sh" || {
      msg_warn "$(hkz_t theme_fail) ${LOG_PATH}"
      msg_info "$(hkz_t theme_later)"
    }
  else
    export HKZ_THEME_CMD=remove HKZ_THEME_VERBOSE=1
    hkz_run_theme_installer "$SCRIPT_DIR/installers/theme.sh" || {
      source "$SCRIPT_DIR/lib/theme-blade.sh" 2>/dev/null || true
      hkz_theme_force_clean 2>/dev/null || true
    }
    msg_ok "$(hkz_t theme_std_ok)"
    msg_info "$(hkz_t theme_later)"
  fi
  install_cli_tool
  setup_auto_update_cron
  hkz_panel_load_install_secrets 2>/dev/null || true
  hkz_panel_print_credentials
}

cmd_theme() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  hkz_panel_files_exist || { msg_err "$(hkz_t theme_panel_missing)"; exit 1; }
  hkz_set_web_user || exit 1
  export HKZ_THEME_VERBOSE=1 HKZ_THEME_REBUILD=1 HKZ_THEME_FORCE=1
  msg_info "$(hkz_t theme_logs) ${LOG_PATH}"
  local theme_src="$SCRIPT_DIR"
  if [ ! -f "${SCRIPT_DIR}/theme/catalog.conf" ] && [ -f "${_SCRIPT_DIR}/theme/catalog.conf" ]; then
    theme_src="$_SCRIPT_DIR"
  fi
  hkz_ensure_theme_pack "$theme_src" || exit 1
  source "$SCRIPT_DIR/lib/ui-theme.sh"
  run_theme_ui
  msg_step "$(hkz_t theme_apply): $(hkz_theme_pending_label)"
  msg_info "$(hkz_t theme_cmd): HKZ_THEME_CMD=${HKZ_THEME_CMD:-?} HKZ_THEME_ID=${HKZ_THEME_ID:-—}"
  hkz_run_theme_installer "$SCRIPT_DIR/installers/theme.sh" || {
    msg_err "$(hkz_t theme_fail_apply) ${LOG_PATH}"
    exit 1
  }
  print_rule
  msg_ok "$(hkz_t theme_current): $(hkz_theme_current_label)"
  print_rule
}

cmd_wings() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  source "$SCRIPT_DIR/lib/ui-wings.sh"
  run_wings_ui || exit 1
  INSTALL_MARIADB=false
  if [ "$WINGS_DBHOST" = true ] && ! command -v mysql >/dev/null 2>&1 && ! command -v mariadb >/dev/null 2>&1; then
    INSTALL_MARIADB=true
  fi
  export INSTALL_MARIADB WINGS_DBHOST
  hkz_wings_save_env
  msg_info "$(hkz_t wings_logs) ${LOG_PATH}"
  msg_step "$(hkz_t wings_install_start)"
  [ -f "$SCRIPT_DIR/installers/wings.sh" ] || {
    msg_err "$(hkz_t wings_install_fail) ${LOG_PATH}"
    exit 1
  }
  hkz_run_wings_installer "$SCRIPT_DIR/installers/wings.sh" || {
    msg_err "$(hkz_t wings_install_fail) ${LOG_PATH}"
    exit 1
  }
  print_rule
  msg_ok "$(hkz_t wings_ready)"
  if systemctl is-active wings >/dev/null 2>&1; then
    msg_ok "$(hkz_t wings_running)"
  else
    msg_info "$(hkz_t wings_start): systemctl start wings"
  fi
  msg_info "$(hkz_t wings_deploy_later): phkz wings-deploy"
  print_rule
}

cmd_wings_deploy() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  local cmd="${*:-}"
  hkz_ensure_wings_etc
  hkz_wings_ensure_binary || exit 1
  if [ -z "$cmd" ]; then
    msg_info "$(hkz_t wings_deploy_hint)"
    echo -en "  $(hkz_t wings_deploy_q) "
    read -r cmd
  fi
  [ -z "$cmd" ] && { msg_info "$(hkz_t wings_deploy_skip)"; exit 0; }
  msg_step "auto-deploy"
  hkz_wings_run_deploy "$cmd" && msg_ok "$(hkz_t wings_deploy_ok)" || {
    msg_err "$(hkz_t wings_deploy_warn)"
    exit 1
  }
  hkz_wings_load_env
  hkz_wings_ensure_node_cert || msg_warn "$(hkz_t wings_cert_warn)"
  hkz_wings_start || msg_warn "$(hkz_t wings_heal_start_fail)"
  msg_ok "$(hkz_t wings_ready)"
}

cmd_uninstall_panel() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  draw_logo
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  if ! hkz_panel_files_exist; then
    msg_warn "$(hkz_t warn_nothing_panel)"
    msg_info "$(hkz_t db_cleanup_orphan)"
    echo -en "  $(hkz_t db_cleanup_orphan_q) "
    read -r c
    [[ ! "$c" =~ ^[Yy] ]] && return 0
    env HKZ_LANG="${HKZ_LANG:-ru}" RM_PANEL=true RM_WINGS=false bash "$SCRIPT_DIR/installers/uninstall.sh"
    return 0
  fi
  hkz_panel_external_install && msg_info "$(hkz_t panel_external_manage)"
  echo -en "  $(hkz_t prompt_remove_panel) "
  read -r c
  [[ ! "$c" =~ ^[Yy] ]] && exit 0
  env HKZ_LANG="${HKZ_LANG:-ru}" RM_PANEL=true RM_WINGS=false bash "$SCRIPT_DIR/installers/uninstall.sh"
}

cmd_uninstall_wings() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  draw_logo
  if ! hkz_wings_files_exist; then
    msg_warn "$(hkz_t warn_nothing_wings)"
    return 0
  fi
  ! hkz_wings_installed_by_us && msg_info "$(hkz_t wings_external_manage)"
  echo -en "  $(hkz_t prompt_remove_wings) "
  read -r c
  [[ ! "$c" =~ ^[Yy] ]] && exit 0
  env HKZ_LANG="${HKZ_LANG:-ru}" RM_PANEL=false RM_WINGS=true bash "$SCRIPT_DIR/installers/uninstall.sh"
}

cmd_uninstall_all() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  draw_logo
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  if ! hkz_panel_files_exist && ! hkz_wings_files_exist; then
    msg_warn "$(hkz_t warn_nothing_all)"
    msg_info "$(hkz_t db_cleanup_orphan)"
    echo -en "  $(hkz_t db_cleanup_orphan_q) "
    read -r c
    [[ ! "$c" =~ ^[Yy] ]] && return 0
    env HKZ_LANG="${HKZ_LANG:-ru}" RM_PANEL=true RM_WINGS=true bash "$SCRIPT_DIR/installers/uninstall.sh"
    return 0
  fi
  hkz_panel_files_exist && msg_info "$(hkz_t info_found_panel)"
  hkz_wings_files_exist && msg_info "$(hkz_t info_found_wings)"
  echo -en "  $(hkz_t prompt_remove_all) "
  read -r c
  [[ ! "$c" =~ ^[Yy] ]] && exit 0
  local rp=false rw=false
  hkz_panel_files_exist && rp=true
  hkz_wings_files_exist && rw=true
  [ "$rp" != true ] && rp=true
  env HKZ_LANG="${HKZ_LANG:-ru}" RM_PANEL="$rp" RM_WINGS="$rw" bash "$SCRIPT_DIR/installers/uninstall.sh"
}

cmd_update() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  env HKZ_LANG="${HKZ_LANG:-ru}" bash "$SCRIPT_DIR/installers/update-panel.sh" 2>&1 | tee -a "$LOG_PATH"
  msg_ok "$(hkz_t update_done)"
}

cmd_repair() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  env HKZ_LANG="${HKZ_LANG:-ru}" bash "$SCRIPT_DIR/installers/repair-wings.sh" 2>&1 | tee -a "$LOG_PATH"
  if hkz_panel_files_exist 2>/dev/null; then
    env HKZ_LANG="${HKZ_LANG:-ru}" bash "$SCRIPT_DIR/installers/repair-panel.sh" 2>&1 | tee -a "$LOG_PATH"
  else
    msg_info "$(hkz_t repair_panel_skip)"
  fi
  print_rule
  msg_ok "$(hkz_t repair_done)"
  print_rule
}

cmd_backup() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  bash "$SCRIPT_DIR/installers/backup.sh"
}

cmd_info() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  source "$SCRIPT_DIR/lib/panel-customize.sh" 2>/dev/null || true
  source "$SCRIPT_DIR/lib/info.sh"
  run_info
}

cmd_self_update() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  hkz_download_installer && install_cli_tool
  hkz_resolve_panel_dir 2>/dev/null || true
  source "$SCRIPT_DIR/lib/theme-blade.sh" 2>/dev/null || true
  if [ -n "$(hkz_theme_read_active_id 2>/dev/null || true)" ] && hkz_panel_files_exist 2>/dev/null; then
    msg_step "$(hkz_t theme_rebuild_active 2>/dev/null || echo 'Rebuilding HKZ theme CSS')"
    hkz_theme_rebuild_active 2>/dev/null || msg_warn "$(hkz_t theme_rebuild_warn 2>/dev/null || echo 'Theme rebuild skipped — run: phkz theme')"
  fi
  msg_ok "v$(read_local_version)"
}

cmd_version() {
  draw_logo
  msg_info "v$(read_local_version) / github $(fetch_remote_version 2>/dev/null || echo ?)"
}

cmd_menu() {
  [[ $EUID -ne 0 ]] && msg_err "$(hkz_t err_root)" && exit 1
  detect_os
  hkz_resolve_panel_dir 2>/dev/null || true
  source "$SCRIPT_DIR/lib/menu.sh"
  run_main_menu
}

main() {
  local cmd="${1:-menu}"
  shift || true
  [ "$1" = "--quiet" ] && shift
  hkz_pick_lang_once "$cmd" "$@"
  hkz_ensure_opt_installer "$cmd" "$@"
  case "$cmd" in
    menu|"") cmd_menu "$@" ;;
    install) cmd_install "$@" ;;
    theme|themes) cmd_theme "$@" ;;
    wings) cmd_wings "$@" ;;
    wings-deploy) cmd_wings_deploy "$@" ;;
    update) cmd_update "$@" ;;
    repair) cmd_repair "$@" ;;
    info) cmd_info "$@" ;;
    status)
      systemctl is-active mariadb nginx pteroq wings 2>/dev/null || true
      ;;
    backup) cmd_backup "$@" ;;
    self-update) cmd_self_update "$@" ;;
    uninstall-panel) cmd_uninstall_panel "$@" ;;
    uninstall-wings) cmd_uninstall_wings "$@" ;;
    uninstall-all) cmd_uninstall_all "$@" ;;
    version|-v) cmd_version "$@" ;;
    help|-h) cmd_menu "$@" ;;
    *) msg_err "$(hkz_t err_unknown): $cmd"; cmd_menu "$@" ;;
  esac
}

main "$@"
