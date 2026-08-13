#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/panel-customize.sh"

export HKZ_THEME_CMD="${HKZ_THEME_CMD:-}"
export HKZ_THEME_ID="${HKZ_THEME_ID:-}"

hkz_theme_ui_pick_locale() {
  local stamp="${HKZ_STAMP_DIR}/panel-locale" cur=ru
  [ -f "$stamp" ] && cur=$(tr -d '[:space:]' <"$stamp")
  cur=$(hkz_panel_normalize_locale "$cur")
  print_rule
  echo "  $(hkz_t theme_ui_locale)"
  echo "  $(hkz_t ui_panel_lang1)"
  echo "  $(hkz_t ui_panel_lang2)"
  echo -en "  $(hkz_t theme_ui_choice_keep): "
  read -r lang_choice
  case "$lang_choice" in
    "") unset PANEL_LOCALE; export PANEL_LOCALE; msg_info "$(hkz_t theme_ui_keep)"; return 0 ;;
    1|en|EN|english|English) PANEL_LOCALE=en ;;
    2|ru|RU|рус) PANEL_LOCALE=ru ;;
    *) msg_err "$(hkz_t ui_panel_lang_bad)"; exit 1 ;;
  esac
  export PANEL_LOCALE
  msg_info "$(hkz_t ui_panel_lang_set): $([ "$PANEL_LOCALE" = ru ] && hkz_t lang_ru || hkz_t lang_en)"
}

run_theme_ui() {
  local catalog
  local choice n=0
  local ids=() names=()

  catalog="$(hkz_theme_catalog_file)"
  draw_logo
  print_rule
  if ! hkz_panel_ready_for_theme; then
    msg_err "$(hkz_t theme_panel_missing)"
    exit 1
  fi
  if [ ! -f "$catalog" ]; then
    msg_err "$(hkz_t theme_catalog_missing) $catalog"
    msg_info "$(hkz_t theme_update_hint)"
    exit 1
  fi
  msg_info "$(hkz_t theme_now) $(hkz_theme_current_label)"
  print_rule
  echo "  $(hkz_t theme_pick_std)"
  echo ""

  while IFS='|' read -r tid tname || [ -n "$tid" ]; do
    [[ -z "$tid" || "$tid" == \#* ]] && continue
    n=$((n + 1))
    ids+=("$tid")
    names+=("$tname")
    printf '  [%d] %s\n' "$n" "$tname"
  done <"$catalog"

  if [ "$n" -lt 1 ]; then
    msg_err "$(hkz_t theme_catalog_empty) $catalog"
    exit 1
  fi

  print_rule
  msg_info "$(hkz_t theme_pick_hint) $n"
  echo -en "  $(hkz_t theme_pick_prompt)"
  read -r choice

  if [ -z "$choice" ] || [ "$choice" = "0" ]; then
    HKZ_THEME_CMD=default
    HKZ_THEME_ID=
  elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$n" ]; then
    HKZ_THEME_ID="${ids[$((choice - 1))]}"
    HKZ_THEME_CMD="$HKZ_THEME_ID"
  else
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    if grep -qE "^${choice}\|" "$catalog" 2>/dev/null; then
      HKZ_THEME_ID="$choice"
      HKZ_THEME_CMD="$choice"
    else
      msg_err "$(hkz_t theme_bad_id)"
      exit 1
    fi
  fi

  export HKZ_THEME_CMD HKZ_THEME_ID

  if [ "$HKZ_THEME_CMD" != default ]; then
    hkz_theme_ui_pick_locale
  fi

  msg_info "$(hkz_t theme_will_apply) $(hkz_theme_pending_label)"
  echo -en "  $(hkz_t theme_apply_q) "
  read -r go
  if [[ "$go" =~ ^[Nn] ]]; then
    msg_info "$(hkz_t theme_cancelled)"
    exit 0
  fi
}
