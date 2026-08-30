#!/bin/bash
set -e

HKZ_INSTALLER_REPO="${HKZ_INSTALLER_REPO:-hakyzmain/HKZPterodactylInstaller}"
HKZ_INSTALLER_BRANCH="${HKZ_INSTALLER_BRANCH:-main}"
HKZ_INSTALL_DIR="${HKZ_INSTALL_DIR:-}"
HKZ_OPT_DIR="${HKZ_OPT_DIR:-/opt/HKZPterodactylInstaller}"
HKZ_INSTALLER_REV="${HKZ_INSTALLER_REV:-114}"

if [ -z "$HKZ_INSTALL_DIR" ]; then
  if [ -d "$HKZ_OPT_DIR" ]; then
    HKZ_INSTALL_DIR="$HKZ_OPT_DIR"
  elif [ -d /opt/phkz ]; then
    HKZ_INSTALL_DIR=/opt/phkz
  elif [ -d /opt/HKZPanelAutoInstaller ]; then
    HKZ_INSTALL_DIR=/opt/HKZPanelAutoInstaller
  else
    HKZ_INSTALL_DIR="$HKZ_OPT_DIR"
  fi
fi
export HKZ_INSTALL_DIR HKZ_OPT_DIR

_hkz_ask_lang() {
  echo "  [1] English"
  echo "  [2] Русский"
  echo -en "  language / язык (Enter — Русский): "
  read -r _hkz_lc
  case "$_hkz_lc" in
    1|en|EN|english|English) export HKZ_LANG=en ;;
    *) export HKZ_LANG=ru ;;
  esac
}

_hkz_sync_echo() {
  local lv="$1" rv="$2"
  if [ "${HKZ_LANG:-ru}" = en ]; then
    if [ -z "$lv" ]; then
      echo "> first install ${HKZ_INSTALL_DIR} (v${rv:-?})"
    else
      echo "> update ${HKZ_INSTALL_DIR} (v${lv} → v${rv:-?})"
    fi
  else
    if [ -z "$lv" ]; then
      echo "> первая установка ${HKZ_INSTALL_DIR} (v${rv:-?})"
    else
      echo "> обновление ${HKZ_INSTALL_DIR} (v${lv} → v${rv:-?})"
    fi
  fi
}

[ -f "${HKZ_INSTALL_DIR}/lib/i18n.sh" ] && . "${HKZ_INSTALL_DIR}/lib/i18n.sh"
if command -v hkz_pick_lang_once >/dev/null 2>&1; then
  hkz_pick_lang_once
else
  _hkz_ask_lang
  export HKZ_LANG_ASKED=1
fi

hkz_remote_version() {
  local b64
  b64=$(curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${HKZ_INSTALLER_REPO}/contents/VERSION?ref=${HKZ_INSTALLER_BRANCH}" 2>/dev/null \
    | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -d '\n')
  [ -n "$b64" ] && echo "$b64" | base64 -d 2>/dev/null | tr -d '[:space:]'
}

hkz_need_sync() {
  local lv rv rev want
  [ ! -f "${HKZ_INSTALL_DIR}/install.sh" ] && return 0
  [ ! -f "${HKZ_INSTALL_DIR}/run.sh" ] && return 0
  [ ! -x /usr/local/bin/phkz ] && return 0
  [ ! -f "${HKZ_INSTALL_DIR}/VERSION" ] && return 0
  rev=""
  [ -f "${HKZ_INSTALL_DIR}/INSTALLER_REV" ] && rev=$(tr -d '[:space:]' <"${HKZ_INSTALL_DIR}/INSTALLER_REV")
  want="${HKZ_INSTALLER_REV:-114}"
  [ "$rev" != "$want" ] && return 0
  rv=$(hkz_remote_version)
  [ -z "$rv" ] && return 1
  lv=$(tr -d '[:space:]' <"${HKZ_INSTALL_DIR}/VERSION")
  [ "$lv" != "$rv" ] && return 0
  return 1
}

hkz_sync_opt() {
  if [ "${HKZ_LANG:-ru}" = en ]; then
    command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 1; }
  else
    command -v curl >/dev/null 2>&1 || { echo "нужен curl"; exit 1; }
  fi
  rm -rf /opt/PterodactylHKZAutoInstaller 2>/dev/null || true
  local lv rv api tmp auth src
  lv=""
  [ -f "${HKZ_INSTALL_DIR}/VERSION" ] && lv=$(tr -d '[:space:]' <"${HKZ_INSTALL_DIR}/VERSION")
  rv=$(hkz_remote_version)
  _hkz_sync_echo "$lv" "$rv"
  api="https://api.github.com/repos/${HKZ_INSTALLER_REPO}"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  auth=(-H "Accept: application/vnd.github+json")
  curl -fsSL "${auth[@]}" "${api}/tarball/${HKZ_INSTALLER_BRANCH}" -o "${tmp}/repo.tar.gz"
  tar -xzf "${tmp}/repo.tar.gz" -C "${tmp}"
  src=$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -1)
  mkdir -p "$HKZ_INSTALL_DIR"
  rm -rf "${HKZ_INSTALL_DIR:?}"/*
  cp -a "${src}/." "${HKZ_INSTALL_DIR}/"
  chmod +x "${HKZ_INSTALL_DIR}/install.sh" "${HKZ_INSTALL_DIR}/run.sh" "${HKZ_INSTALL_DIR}/i.sh" \
    "${HKZ_INSTALL_DIR}/installers/"*.sh 2>/dev/null || true
  sed -i 's/\r$//' "${HKZ_INSTALL_DIR}/install.sh" "${HKZ_INSTALL_DIR}/run.sh" "${HKZ_INSTALL_DIR}/i.sh" 2>/dev/null || true
  mkdir -p /usr/local/bin
  cat > /usr/local/bin/phkz <<EOF
#!/bin/bash
export HKZ_INSTALL_DIR="${HKZ_INSTALL_DIR}"
unset HKZ_LANG HKZ_LANG_ASKED
exec bash "${HKZ_INSTALL_DIR}/run.sh" "\$@"
EOF
  chmod +x /usr/local/bin/phkz
}

if hkz_need_sync; then
  hkz_sync_opt
fi

export HKZ_INSTALLER_SYNCED=1 HKZ_LANG="${HKZ_LANG:-ru}" HKZ_LANG_ASKED=1
exec bash "${HKZ_INSTALL_DIR}/install.sh" "$@"
