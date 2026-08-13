#!/bin/bash

HKZ_PTERORUS_URL="${HKZ_PTERORUS_URL:-https://github.com/Kanorto/pterorus/archive/refs/heads/main.tar.gz}"
HKZ_COPYRIGHT_TEXT="${HKZ_COPYRIGHT_TEXT:-HAKYZ LLC}"

hkz_panel_normalize_locale() {
  case "${1:-en}" in
    ru|russian|rus|рус|русский) echo ru ;;
    en|english|eng|англ|английский) echo en ;;
    *) echo en ;;
  esac
}

hkz_panel_env_val() {
  local key="$1" file="${PANEL_DIR}/.env" line
  [ -f "$file" ] || return 1
  line=$(grep -E "^${key}=" "$file" 2>/dev/null | tail -1) || return 1
  line=${line#*=}
  line=$(echo "$line" | sed -e 's/^["'\'']//' -e 's/["'\'']$//')
  printf '%s' "$line"
}

hkz_panel_load_db_from_env() {
  [ -f "${PANEL_DIR}/.env" ] || return 1
  MYSQL_DB="${MYSQL_DB:-$(hkz_panel_env_val DB_DATABASE)}"
  MYSQL_USER="${MYSQL_USER:-$(hkz_panel_env_val DB_USERNAME)}"
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(hkz_panel_env_val DB_PASSWORD)}"
  MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-$(hkz_panel_env_val DB_HOST)}"
  MYSQL_DB="${MYSQL_DB:-panel}"
  MYSQL_USER="${MYSQL_USER:-pterodactyl}"
  MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"
  export MYSQL_DB MYSQL_USER MYSQL_PASSWORD MYSQL_DBHOST_HOST
  [ -n "$MYSQL_PASSWORD" ] || return 1
  return 0
}

hkz_panel_env_set() {
  local file="$1" key="$2" val="$3"
  [ -f "$file" ] || return 1
  HKZ_ENV_FILE="$file" HKZ_ENV_KEY="$key" HKZ_ENV_VAL="$val" php -r '
    $f = getenv("HKZ_ENV_FILE");
    $k = getenv("HKZ_ENV_KEY");
    $v = getenv("HKZ_ENV_VAL");
    $lines = file_exists($f) ? file($f, FILE_IGNORE_NEW_LINES) : [];
    $out = [];
    $done = false;
    foreach ($lines as $line) {
      if (str_starts_with($line, $k . "=")) {
        $out[] = $k . "=" . json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $done = true;
      } else {
        $out[] = $line;
      }
    }
    if (!$done) {
      $out[] = $k . "=" . json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
    file_put_contents($f, implode("\n", $out) . "\n");
  '
}

hkz_panel_ensure_settings_ui() {
  local env="${PANEL_DIR}/.env"
  [ -f "$env" ] || return 1
  sed -i '/^APP_ENVIRONMENT_ONLY=/d' "$env"
  printf 'APP_ENVIRONMENT_ONLY=false\n' >>"$env"
  rm -f "${PANEL_DIR}/bootstrap/cache/config.php" 2>/dev/null || true
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction) >>"${LOG_PATH:-/dev/null}" 2>&1 || true
  log "[panel] APP_ENVIRONMENT_ONLY=false (settings UI enabled)"
  return 0
}

hkz_panel_ensure_service_author() {
  local env="${PANEL_DIR}/.env" author=""
  [ -f "$env" ] || return 1
  author=$(hkz_panel_env_val APP_SERVICE_AUTHOR 2>/dev/null || true)
  if [ -n "$author" ] && [[ "$author" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    return 0
  fi
  author="${email:-${user_email:-}}"
  if [ -z "$author" ] || ! [[ "$author" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    hkz_panel_load_db_from_env 2>/dev/null || true
    if [ -n "${MYSQL_PASSWORD:-}" ]; then
      author=$(mariadb -h "${MYSQL_DBHOST_HOST:-127.0.0.1}" -u "${MYSQL_USER:-pterodactyl}" -p"$MYSQL_PASSWORD" "${MYSQL_DB:-panel}" -Nse \
        "SELECT email FROM users WHERE root_admin=1 ORDER BY id ASC LIMIT 1;" 2>/dev/null || true)
    fi
  fi
  if [ -z "$author" ] || ! [[ "$author" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    author="admin@localhost.local"
  fi
  sed -i '/^APP_SERVICE_AUTHOR=/d' "$env"
  printf 'APP_SERVICE_AUTHOR=%s\n' "$author" >>"$env"
  rm -f "${PANEL_DIR}/bootstrap/cache/config.php" 2>/dev/null || true
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction) >>"${LOG_PATH:-/dev/null}" 2>&1 || true
  log "[panel] APP_SERVICE_AUTHOR=${author}"
  return 0
}

hkz_panel_ensure_db_env() {
  local user="${1:-$MYSQL_USER}" pass="${2:-$MYSQL_PASSWORD}" db="${3:-$MYSQL_DB}" env="${PANEL_DIR}/.env"
  local host="${MYSQL_DBHOST_HOST:-localhost}"
  [ -f "$env" ] || return 1
  [ -n "$pass" ] || return 1
  if ! hkz_mysql_test_connection "$user" "$pass" "" "$db"; then
    return 1
  fi
  host="${MYSQL_DBHOST_HOST:-localhost}"
  hkz_panel_env_set "$env" DB_HOST "$host"
  hkz_panel_env_set "$env" DB_PORT "3306"
  hkz_panel_env_set "$env" DB_DATABASE "$db"
  hkz_panel_env_set "$env" DB_USERNAME "$user"
  hkz_panel_env_set "$env" DB_PASSWORD "$pass"
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction 2>/dev/null) || true
  return 0
}

hkz_panel_ensure_dynamic_app_name() {
  rm -f "${PANEL_DIR}/bootstrap/cache/config.php" 2>/dev/null || true
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
  return 0
}

hkz_panel_read_setting() {
  local key="$1" val
  hkz_panel_load_db_from_env || return 1
  val=$(mariadb -h "$MYSQL_DBHOST_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" -Nse \
    "SELECT \`value\` FROM settings WHERE \`key\`='settings::${key}' LIMIT 1;" 2>/dev/null) || return 1
  printf '%s' "$val"
}

hkz_panel_patch_config_app_name() {
  return 0
}

hkz_panel_patch_settings_company_name() {
  return 0
}

hkz_panel_patch_strings_copyright() {
  local loc f text="${HKZ_COPYRIGHT_TEXT}"
  text=$(echo "$text" | sed "s/'/\\\\'/g")
  for loc in en ru; do
    f="${PANEL_DIR}/resources/lang/${loc}/strings.php"
    [ -f "$f" ] || continue
    if grep -q "'copyright'" "$f"; then
      sed -i "s|'copyright' => '[^']*'|'copyright' => '${text}'|g" "$f"
      sed -i "s|\"copyright\" => \"[^\"]*\"|\"copyright\" => \"${text}\"|g" "$f"
    else
      sed -i "/^];/i\\    'copyright' => '${text}'," "$f" 2>/dev/null || true
    fi
  done
  msg_ok "strings.php → ${HKZ_COPYRIGHT_TEXT}"
}

hkz_panel_patch_admin_logo() {
  local admin="${PANEL_DIR}/resources/views/layouts/admin.blade.php"
  [ -f "$admin" ] || return 0

  if grep -q 'class="logo"' "$admin"; then
    if command -v perl >/dev/null 2>&1; then
      perl -i -pe '
        if (/class="logo"/) {
          s/href="#"/href="{{ route('\''index'\'') }}"/g;
          s/href="\{\{\s*url\(['\''"]\/['\''"]\)\s*\}\}"/href="{{ route('\''index'\'') }}"/g;
          unless (/data-hkz-home/) { s/(class="logo")/data-hkz-home="1" $1/; }
        }
      ' "$admin" 2>>"$LOG_PATH" || true
    fi
    sed -i 's|<a href="#" class="logo"|<a href="{{ route('\''index'\'') }}" class="logo" data-hkz-home="1"|g' "$admin" 2>/dev/null || true
    sed -i 's|class="logo"|class="logo" data-hkz-home="1"|g' "$admin" 2>/dev/null || true
  fi
  msg_ok "логотип админки → главная (route index)"
}

hkz_panel_patch_admin_footer() {
  local admin="${PANEL_DIR}/resources/views/layouts/admin.blade.php"
  local repl='@lang('\''strings.copyright'\'', ['\''year'\'' => date('\''Y'')]) <!-- HKZ-AURORA-FOOTER -->'

  [ -f "$admin" ] || { msg_warn "admin.blade.php не найден"; return 1; }

  if grep -q 'HKZ-AURORA-FOOTER' "$admin" && ! grep -qi 'pterodactyl' "$admin"; then
    msg_ok "футер админки: ${HKZ_COPYRIGHT_TEXT}"
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    HKZ_FOOTER_REPL="$repl" perl -0777 -i -pe '
      my $r = $ENV{HKZ_FOOTER_REPL};
      s/Copyright\s*(?:&copy;|©)\s*2015\s*-\s*\{\{\s*date\([^)]+\)\s*\}\}[^<]*Pterodactyl[^<]*\.?/$r/gi;
      s/Copyright\s*©\s*2015\s*-\s*\{\{\s*date\(['\''"]Y['\''"]\)\s*\}\}\s*Pterodactyl\s*Software\.?\s*/$r/gi;
      s/Pterodactyl®?\s*(?:©|&copy;)\s*2015\s*-\s*(?:\{\{\s*date\([^)]+\)\s*\}\}|20\d{2})[^<\n]*/$r/gi;
      s/@lang\([^)]*strings\.copyright[^)]*\)\s*<!--\s*HKZ-AURORA-FOOTER\s*-->/$r/g;
    ' "$admin" 2>>"$LOG_PATH" || true
  fi

  if ! grep -q 'HKZ-AURORA-FOOTER' "$admin" || grep -qi 'pterodactyl' "$admin"; then
    sed -i "s|Copyright © 2015 - {{ date('Y') }} Pterodactyl Software.|${repl}|g" "$admin" 2>/dev/null || true
    sed -i 's|Copyright © 2015 - {{ date('\''Y'\'') }} Pterodactyl Software.|'"${repl}"'|g' "$admin" 2>/dev/null || true
    sed -i 's|Copyright &copy; 2015 - {{ date('\''Y'\'') }} <a href="https://pterodactyl.io/">Pterodactyl Software</a>.|'"${repl}"'|g' "$admin" 2>/dev/null || true
    sed -i 's|Pterodactyl® © 2015 - {{ date('\''Y'\'') }}|'"${repl}"'|g' "$admin" 2>/dev/null || true
    sed -i 's|Pterodactyl® © 2015 - 20[0-9][0-9][^<]*|'"${repl}"'|g' "$admin" 2>/dev/null || true
    sed -i 's|Pterodactyl® © 2015 - 2026|'"${repl}"'|g' "$admin" 2>/dev/null || true
    sed -i 's|Pterodactyl® © 2015 - 20[0-9][0-9]|'"${repl}"'|g' "$admin" 2>/dev/null || true
  fi

  if grep -q 'HKZ-AURORA-FOOTER' "$admin" && ! grep -qi 'pterodactyl\.io' "$admin"; then
    msg_ok "футер админки: ${HKZ_COPYRIGHT_TEXT}"
    return 0
  fi

  msg_warn "не удалось заменить футер в admin.blade.php"
  return 1
}

hkz_panel_patch_settings_password_optional() {
  local f
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    grep -q 'current_password:admin' "$f" 2>/dev/null || continue
    sed -i "s/'password' => 'required|current_password:admin'/'password' => 'nullable|current_password:admin'/g" "$f"
    sed -i "s/'password' => \[.required., .current_password:admin.\]/'password' => ['nullable', 'current_password:admin']/g" "$f"
    sed -i "s/required|current_password:admin/nullable|current_password:admin/g" "$f"
    log "[panel] password optional: $f"
  done < <(find "${PANEL_DIR}/app" -type f -name '*.php' -print0 2>/dev/null)
  msg_ok "сохранение настроек без обязательного пароля"
}

hkz_panel_install_ru_lang() {
  local lang_dir="${PANEL_DIR}/resources/lang" tmp
  [ -d "$lang_dir/en" ] || { msg_err "нет $lang_dir/en"; return 1; }

  if [ -d "$lang_dir/ru" ] && [ -f "$lang_dir/ru/strings.php" ] && [ "${HKZ_FORCE_RU_LANG:-0}" != 1 ]; then
    msg_ok "resources/lang/ru уже есть — пропуск загрузки pterorus"
    return 0
  fi

  msg_step "русский язык панели"
  rm -rf "$lang_dir/ru"
  cp -a "$lang_dir/en" "$lang_dir/ru"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  if hkz_download "$HKZ_PTERORUS_URL" "$tmp/pterorus.tar.gz" "перевод pterorus"; then
    tar -xzf "$tmp/pterorus.tar.gz" -C "$tmp"
    local src
    src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [ -d "$src/ru" ]; then
      cp -a "$src/ru/." "$lang_dir/ru/"
      msg_ok "наложен перевод Kanorto/pterorus"
    fi
  else
    msg_warn "pterorus не скачан — оставлена копия en → ru"
  fi
  msg_ok "resources/lang/ru"
}

hkz_panel_set_settings_locale() {
  local loc="$1"
  hkz_panel_load_db_from_env || return 1
  mariadb -h "$MYSQL_DBHOST_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" -e \
    "INSERT INTO settings (\`key\`, \`value\`) VALUES ('app:locale', '${loc}')
     ON DUPLICATE KEY UPDATE \`value\`='${loc}';" >>"$LOG_PATH" 2>&1 || return 1
  log "[panel] settings app:locale=${loc}"
}

hkz_panel_set_users_language() {
  local loc db
  loc=$(hkz_panel_normalize_locale "${PANEL_LOCALE:-en}")
  [ -f "${PANEL_DIR}/artisan" ] || return 0
  hkz_panel_load_db_from_env || {
    msg_warn "не удалось прочитать DB из ${PANEL_DIR}/.env — язык пользователей не обновлён"
    return 1
  }
  db="${MYSQL_DB}"
  mariadb -h "$MYSQL_DBHOST_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$db" -e \
    "UPDATE users SET language='${loc}';" >>"$LOG_PATH" 2>&1 || return 1
  log "[panel] users.language=${loc}"
}

hkz_panel_artisan_locale_refresh() {
  [ -f "${PANEL_DIR}/artisan" ] || return 0
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
  (cd "$PANEL_DIR" && php artisan cache:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
  (cd "$PANEL_DIR" && php artisan view:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
  (cd "$PANEL_DIR" && php artisan route:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
}

hkz_panel_apply_locale() {
  local loc
  loc=$(hkz_panel_normalize_locale "${PANEL_LOCALE:-ru}")
  export PANEL_LOCALE="$loc"
  msg_step "язык панели: ${loc}"

  if [ "$loc" = ru ]; then
    hkz_panel_install_ru_lang || msg_warn "русский язык — частично"
  fi

  local env="${PANEL_DIR}/.env"
  if grep -q '^APP_LOCALE=' "$env" 2>/dev/null; then
    sed -i "s/^APP_LOCALE=.*/APP_LOCALE=${loc}/" "$env"
  else
    echo "APP_LOCALE=${loc}" >>"$env"
  fi
  if grep -q '^APP_FALLBACK_LOCALE=' "$env" 2>/dev/null; then
    sed -i 's/^APP_FALLBACK_LOCALE=.*/APP_FALLBACK_LOCALE=en/' "$env"
  else
    echo 'APP_FALLBACK_LOCALE=en' >>"$env"
  fi

  hkz_panel_set_settings_locale "$loc" || msg_warn "settings.app:locale — см. лог"
  hkz_panel_set_users_language || msg_warn "users.language — см. лог"
  hkz_panel_artisan_locale_refresh
  mkdir -p "$HKZ_STAMP_DIR"
  echo "$loc" >"${HKZ_STAMP_DIR}/panel-locale"
  msg_ok "язык: APP_LOCALE=${loc}, users + settings"
}

hkz_panel_revert_strings_copyright() {
  local loc f
  for loc in en ru; do
    f="${PANEL_DIR}/resources/lang/${loc}/strings.php"
    [ -f "$f" ] || continue
    if grep -q "'copyright'" "$f"; then
      sed -i "s|'copyright' => '[^']*'|'copyright' => 'Pterodactyl® © 2015 - :year'|g" "$f"
      sed -i "s|\"copyright\" => \"[^\"]*\"|\"copyright\" => \"Pterodactyl® © 2015 - :year\"|g" "$f"
    fi
  done
}

hkz_panel_restore_stock_app_name_files() {
  local root
  if ! declare -F hkz_theme_restore_stock_file >/dev/null 2>&1; then
    return 0
  fi
  root=$(hkz_theme_fetch_stock_root 2>/dev/null) || root=""
  [ -n "$root" ] || return 0
  hkz_theme_restore_stock_file "$root" "config/app.php" || true
  hkz_theme_restore_stock_file "$root" "app/Http/Controllers/Admin/Settings/IndexController.php" || true
  hkz_theme_restore_stock_file "$root" "resources/views/admin/settings/index.blade.php" || true
  return 0
}

hkz_panel_apply_branding() {
  msg_step "брендинг ${HKZ_COPYRIGHT_TEXT}"
  hkz_panel_restore_stock_app_name_files
  hkz_panel_patch_strings_copyright
  hkz_panel_patch_admin_logo
  hkz_panel_patch_admin_footer || msg_warn "футер — см. ${LOG_PATH}"
  (cd "$PANEL_DIR" && php artisan view:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
  (cd "$PANEL_DIR" && php artisan config:clear --no-interaction) >>"$LOG_PATH" 2>&1 || true
  msg_ok "копирайт: ${HKZ_COPYRIGHT_TEXT}"
}

hkz_panel_revert_branding() {
  hkz_panel_revert_strings_copyright
  if declare -F hkz_theme_restore_stock_file >/dev/null 2>&1; then
    local root
    root=$(hkz_theme_fetch_stock_root 2>/dev/null) || root=""
    if [ -n "$root" ]; then
      hkz_theme_restore_stock_file "$root" "resources/views/layouts/admin.blade.php" || true
      hkz_theme_scrub_branding 2>/dev/null || true
    fi
  fi
}

hkz_panel_apply_customization() {
  hkz_panel_ensure_settings_ui || true
  hkz_panel_ensure_service_author || true
  hkz_panel_apply_locale || return 1
  hkz_panel_patch_settings_password_optional || true
}
