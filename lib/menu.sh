#!/bin/bash

run_main_menu() {
  draw_logo
  while true; do
    print_rule
    echo "  [0] $(hkz_t menu_0)"
    echo "  [1] $(hkz_t menu_1)"
    echo "  [2] $(hkz_t menu_2)"
    echo "  [3] $(hkz_t menu_3)"
    echo "  [4] $(hkz_t menu_4)"
    echo "  [5] $(hkz_t menu_5)"
    echo "  [6] $(hkz_t menu_6)"
    echo "  [7] $(hkz_t menu_7)"
    echo "  [8] $(hkz_t menu_8)"
    echo "  [9] $(hkz_t menu_9)"
    print_rule
    echo -en "  $(hkz_t menu_choice): "
    read -r choice
    case "$choice" in
      0) cmd_install; return ;;
      1) cmd_wings; return ;;
      2) cmd_install; cmd_wings; return ;;
      3) cmd_uninstall_panel; return ;;
      4) cmd_uninstall_wings; return ;;
      5) cmd_uninstall_all; return ;;
      6) cmd_update; return ;;
      7) cmd_info; return ;;
      8) cmd_theme; return ;;
      9|q|Q|exit) exit 0 ;;
      *) msg_err "$(hkz_t menu_invalid)" ;;
    esac
  done
}
