#!/bin/bash

HKZ_INSTALLER_REPO="${HKZ_INSTALLER_REPO:-hakyzmain/HKZPterodactylInstaller}"
HKZ_INSTALLER_BRANCH="${HKZ_INSTALLER_BRANCH:-main}"
HKZ_INSTALL_DIR="${HKZ_INSTALL_DIR:-}"

github_auth_header() {
  if [ -n "$GITHUB_TOKEN" ]; then
    echo "Authorization: Bearer ${GITHUB_TOKEN}"
  fi
}

github_raw_url() {
  echo "https://raw.githubusercontent.com/${HKZ_INSTALLER_REPO}/${HKZ_INSTALLER_BRANCH}/$1"
}

fetch_remote_version() {
  local api b64 args=(-H "Accept: application/vnd.github+json")
  api="https://api.github.com/repos/${HKZ_INSTALLER_REPO}/contents/VERSION"
  [ -n "$GITHUB_TOKEN" ] && args=(-H "$(github_auth_header)" -H "Accept: application/vnd.github+json")
  b64=$(curl -fsSL "${args[@]}" "${api}?ref=${HKZ_INSTALLER_BRANCH}" 2>/dev/null \
    | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -d '\n')
  [ -n "$b64" ] && echo "$b64" | base64 -d 2>/dev/null | tr -d '[:space:]'
}

version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]
}

read_local_version() {
  local f="${1:-$SCRIPT_DIR/VERSION}"
  [ -f "$f" ] && tr -d '[:space:]' <"$f" || echo "$INSTALLER_VERSION"
}

check_installer_update() {
  local remote local_v
  local_v=$(read_local_version)
  remote=$(fetch_remote_version) || true
  [ -z "$remote" ] && return 1
  if version_gt "$remote" "$local_v"; then
    echo "$remote"
    return 0
  fi
  return 1
}

self_update_installer() {
  local remote="${1:-$(fetch_remote_version)}"
  [ -z "$remote" ] && return 1
  msg_step "обновление установщика"
  local tmp api args=(-H "Accept: application/vnd.github+json")
  tmp=$(mktemp -d)
  api="https://api.github.com/repos/${HKZ_INSTALLER_REPO}"
  [ -n "$GITHUB_TOKEN" ] && args=(-H "$(github_auth_header)" -H "Accept: application/vnd.github+json")
  curl -fsSL "${args[@]}" "${api}/tarball/${HKZ_INSTALLER_BRANCH}" -o "${tmp}/repo.tar.gz"
  tar -xzf "${tmp}/repo.tar.gz" -C "${tmp}"
  src=$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -1)
  mkdir -p "$HKZ_INSTALL_DIR"
  cp -a "${src}/." "${HKZ_INSTALL_DIR}/"
  chmod +x "${HKZ_INSTALL_DIR}/install.sh" "${HKZ_INSTALL_DIR}/run.sh" "${HKZ_INSTALL_DIR}/i.sh" "${HKZ_INSTALL_DIR}/installers/"*.sh 2>/dev/null || true
  rm -rf "${tmp}"
  INSTALLER_VERSION=$(read_local_version "${HKZ_INSTALL_DIR}/VERSION")
  msg_ok "v${INSTALLER_VERSION}"
}
