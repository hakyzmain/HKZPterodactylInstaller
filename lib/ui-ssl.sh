#!/bin/bash

run_ssl_menu() {
  draw_logo
  while true; do
    print_rule
    echo "  $(hkz_t ssl_menu_title)"
    print_rule
    echo "  [1] $(hkz_t ssl_menu_status)"
    echo "  [2] $(hkz_t ssl_menu_issue)"
    echo "  [3] $(hkz_t ssl_menu_issue_node)"
    echo "  [4] $(hkz_t ssl_menu_renew)"
    echo "  [5] $(hkz_t ssl_menu_remove)"
    echo "  [6] $(hkz_t ssl_menu_disable_node)"
    echo "  [0] $(hkz_t ssl_menu_back)"
    print_rule
    echo -en "  $(hkz_t menu_choice): "
    read -r choice
    case "$choice" in
      1) hkz_ssl_status; print_rule ;;
      2) hkz_ssl_issue_panel; print_rule ;;
      3) hkz_ssl_issue_node; print_rule ;;
      4) hkz_ssl_renew_panel; print_rule ;;
      5) hkz_ssl_remove_panel; print_rule ;;
      6) hkz_ssl_disable_node; print_rule ;;
      0|b|B|q|Q) return 0 ;;
      *) msg_err "$(hkz_t menu_invalid)" ;;
    esac
  done
}
