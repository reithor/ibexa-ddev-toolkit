#!/usr/bin/env bash
#
# Non-interactive port of the /ibexa-dxp-install skill (itself a port of the
# ddev-ibexa-installer DDEV add-on). Provisions DDEV, runs the Composer
# install, and finishes with ibexa:install — driven entirely by flags/env
# vars instead of a TUI, so it can run unattended and be re-run to resume.
#
# Usage: ./install-ibexa-dxp.sh [options]
# Run --help for the full option list.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

marker_done() { [ -f "$1" ]; }
mark()        { date > "$1"; }

# ---------------------------------------------------------------------------
# Defaults (mirrors "Recommended defaults" in configuration-matrix.md)
# ---------------------------------------------------------------------------

: "${DXP_EDITION:=experience}"
: "${PRODUCT_VERSION:=~5.0.0}"
: "${PHP_VERSION:=8.3}"
: "${NODE_VERSION:=22}"
: "${HTTP_SERVER:=nginx-fpm}"
: "${DATABASE:=mariadb}"
: "${DATABASE_VERSION:=10.11}"
: "${HTTP_CACHE:=symfony}"
: "${APP_CACHE:=filesystem}"
: "${SEARCH_ENGINE:=legacy}"
: "${INSTALL_SAMPLE_DATA:=false}"
: "${INSTALL_PROFILER:=true}"
: "${APP_ENV:=dev}"
: "${INSTALL_CLOUD_CONFIG:=false}"
: "${PROJECT_NAME:=}"
: "${INITIAL_BRANCH:=main}"
: "${FORCE_REINSTALL:=false}"
: "${ASSUME_EXISTING:=}"

usage() {
  cat <<'EOF'
Usage: install-ibexa-dxp.sh [options]

  --edition=oss|headless|experience|commerce   (default: experience)
  --release=VERSION      Composer constraint, e.g. ~5.0.0, ~5.0.x-dev, 5.0.3
  --php=VERSION          (default: 8.3; forced/validated per release;
                          6.0.x: 8.5, or 8.6 with DDEV >= 1.25.5)
  --node=VERSION         (default: 22; forced on 5.0.x/6.0.x: 24, or 22
                          for exact releases 5.0.0 - 5.0.10)
  --webserver=nginx-fpm|apache-fpm
  --database=mariadb|mysql|postgres
  --db-version=VERSION
  --http-cache=symfony|varnish
  --app-cache=filesystem|redis|valkey|memcached
  --search-engine=legacy|elasticsearch|elasticsearch8|solr
  --sample-data=true|false
  --profiler=true|false
  --app-env=dev|prod
  --cloud=true|false      Provision Ibexa Cloud (Upsun/platform.sh) config
  --project-name=NAME     Defaults to the current directory name
  --initial-branch=NAME   (default: main)
  --force-reinstall       Ignore .ddev/.ibexa-dxp-installed and re-run
  -h, --help

All settings can also be provided as environment variables of the same
name (DXP_EDITION, PRODUCT_VERSION, PHP_VERSION, ...). Re-running the script
in a partially-provisioned directory resumes from the last completed phase.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --edition=*)        DXP_EDITION="${arg#*=}" ;;
    --release=*)         PRODUCT_VERSION="${arg#*=}" ;;
    --php=*)             PHP_VERSION="${arg#*=}" ;;
    --node=*)            NODE_VERSION="${arg#*=}" ;;
    --webserver=*)       HTTP_SERVER="${arg#*=}" ;;
    --database=*)        DATABASE="${arg#*=}" ;;
    --db-version=*)      DATABASE_VERSION="${arg#*=}" ;;
    --http-cache=*)      HTTP_CACHE="${arg#*=}" ;;
    --app-cache=*)       APP_CACHE="${arg#*=}" ;;
    --search-engine=*)   SEARCH_ENGINE="${arg#*=}" ;;
    --sample-data=*)     INSTALL_SAMPLE_DATA="${arg#*=}" ;;
    --profiler=*)        INSTALL_PROFILER="${arg#*=}" ;;
    --app-env=*)         APP_ENV="${arg#*=}" ;;
    --cloud=*)           INSTALL_CLOUD_CONFIG="${arg#*=}" ;;
    --project-name=*)    PROJECT_NAME="${arg#*=}" ;;
    --initial-branch=*)  INITIAL_BRANCH="${arg#*=}" ;;
    --force-reinstall)   FORCE_REINSTALL="true" ;;
    -h|--help)           usage; exit 0 ;;
    *) die "Unknown option: $arg (see --help)" ;;
  esac
done

[ -n "${PROJECT_NAME}" ] || PROJECT_NAME="$(basename "$PWD")"

# ---------------------------------------------------------------------------
# Phase 1 — Preflight
# ---------------------------------------------------------------------------

version_ge() { # version_ge <actual> <required>
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

preflight_ddev() {
  command -v ddev >/dev/null 2>&1 || \
    die "DDEV not found. Install it: https://ddev.readthedocs.io/en/stable/users/install/ddev-installation/"
  DDEV_VERSION="$(ddev version -j | jq -r '.raw.version' | sed 's/^v//')"
  version_ge "$DDEV_VERSION" "1.24.3" || die "DDEV $DDEV_VERSION found, but >= 1.24.3 is required."
}

detect_existing_project() {
  EXISTING_PROJECT="false"
  if [ -f composer.lock ] || [ -d vendor ]; then
    EXISTING_PROJECT="true"
  fi
}

preflight_workdir() {
  if [ -f "$SETTINGS_FILE" ]; then
    log "Settings file found — resuming, skipping working-directory checks."
    return
  fi

  detect_existing_project
  if [ "$EXISTING_PROJECT" = "true" ]; then
    log "Existing project detected (composer.lock/vendor present) — skipping product questions."
    detect_existing_settings
    INSTALL_PROFILER="false"
    INSTALL_SAMPLE_DATA="false"
    INSTALL_CLOUD_CONFIG="false"
    return
  fi

  local entries
  entries="$(find . -mindepth 1 -maxdepth 1 -not -name .ddev | wc -l)"
  if [ "$entries" -gt 0 ]; then
    [ "$ASSUME_EXISTING" = "true" ] && return
    die "Directory is non-empty but has no composer.lock/vendor — refusing to guess. Empty it, or re-run with --force-reinstall if this is a resumable prior attempt."
  fi
}

detect_existing_settings() {
  local version edition
  if [ -f composer.lock ] && command -v jq >/dev/null 2>&1; then
    version="$(jq -r '.packages[] | select(.name == "ibexa/oss") | .version' composer.lock 2>/dev/null | sed 's/^v//')"
  fi
  if [ -z "${version:-}" ] && [ -f composer.json ] && command -v jq >/dev/null 2>&1; then
    version="$(jq -r '.extra."branch-alias"."dev-main" // empty' composer.json 2>/dev/null)"
  fi
  [ -n "${version:-}" ] && PRODUCT_VERSION="$version"

  if [ -f composer.json ] && command -v jq >/dev/null 2>&1; then
    edition="$(jq -r '.name // empty' composer.json 2>/dev/null)"
    if [ -z "$edition" ] || [ "$edition" = "ibexa/website-skeleton" ]; then
      edition="$(jq -r '.require | keys[] | select(startswith("ibexa/commerce") or startswith("ibexa/experience") or startswith("ibexa/headless") or startswith("ibexa/content"))' composer.json 2>/dev/null | head -n1)"
    fi
    edition="${edition#ibexa/}"
    edition="${edition%-skeleton}"
    [ -n "$edition" ] && DXP_EDITION="$edition"
  fi
  log "Detected: edition=$DXP_EDITION release=$PRODUCT_VERSION"
}

detect_cloud_presets() {
  [ -f .platform.app.yaml ] || return 0
  log "Ibexa Cloud config files found — seeding defaults from them."
  local php_type db_type_ver
  php_type="$(grep -m1 '^type:' .platform.app.yaml | sed -E 's/type:\s*php:([0-9.]+).*/\1/')"
  [ -n "$php_type" ] && PHP_VERSION="$php_type"
  if [ -f .platform/services.yaml ]; then
    db_type_ver="$(grep -A2 '^mysqldb:' .platform/services.yaml | grep 'type:' | sed -E 's/.*type:\s*([a-z]+):([0-9.]+).*/\1 \2/')"
    if [ -n "$db_type_ver" ]; then
      DATABASE="$(awk '{print $1}' <<<"$db_type_ver")"
      DATABASE_VERSION="$(awk '{print $2}' <<<"$db_type_ver")"
    fi
    grep -q 'rediscache' .platform/services.yaml 2>/dev/null && APP_CACHE="redis"
    if grep -q '^varnish' .platform/services.yaml 2>/dev/null; then HTTP_CACHE="varnish"; else HTTP_CACHE="symfony"; fi
    grep -q '^elasticsearch' .platform/services.yaml 2>/dev/null && SEARCH_ENGINE="elasticsearch"
    grep -q '^solrsearch' .platform/services.yaml 2>/dev/null && SEARCH_ENGINE="solr"
  fi
}

SETTINGS_FILE=".ddev/.ibexa-instance-settings"

check_already_installed() {
  if marker_done .ddev/.ibexa-dxp-installed && [ "$FORCE_REINSTALL" != "true" ]; then
    log "Already installed ($(cat .ddev/.ibexa-dxp-installed)). Re-run with --force-reinstall to redo."
    show_report
    exit 0
  fi
}

preflight_composer_auth() {
  [ "$DXP_EDITION" = "oss" ] && return 0
  local ddev_dir="$HOME/.ddev"
  local auth_files=("$ddev_dir/homeadditions/.composer/auth.json" ".ddev/homeadditions/.composer/auth.json")
  local f
  for f in "${auth_files[@]}"; do
    if [ -f "$f" ] && command -v jq >/dev/null 2>&1 && jq -e '.["http-basic"]["updates.ibexa.co"]' "$f" >/dev/null 2>&1; then
      return 0
    fi
  done
  die "No Composer auth for updates.ibexa.co found (checked $ddev_dir/homeadditions/.composer/auth.json and ./.ddev/homeadditions/.composer/auth.json). Non-OSS editions need a licence — see the 'Composer authentication' section of the ibexa-dxp-install skill, then re-run."
}

# ---------------------------------------------------------------------------
# Phase 2/matrix — derive + validate configuration
# ---------------------------------------------------------------------------

derive_product_branch() {
  case "$PRODUCT_VERSION" in
    *4.6.*) PRODUCT_BRANCH="4.6" ;;
    *5.0.*) PRODUCT_BRANCH="5.0" ;;
    *6.0.*) PRODUCT_BRANCH="6.0" ;;
    *)      PRODUCT_BRANCH="5.0" ;;
  esac
  case "$PRODUCT_VERSION" in *-dev*) IS_DEV="true" ;; *) IS_DEV="false" ;; esac
}

product_type_for_edition() {
  case "$DXP_EDITION" in
    oss)        PRODUCT_TYPE="Ibexa OSS" ;;
    headless)   PRODUCT_TYPE="Ibexa DXP Headless" ;;
    experience) PRODUCT_TYPE="Ibexa DXP Experience" ;;
    commerce)   PRODUCT_TYPE="Ibexa DXP Commerce" ;;
    *) die "Unknown --edition=$DXP_EDITION (want oss|headless|experience|commerce)" ;;
  esac
}

force_matrix_values() {
  case "$PRODUCT_BRANCH" in
    4.6) : ;; # PHP 8.3/8.2/8.1 all valid
    5.0) [ "$PHP_VERSION" = "8.3" ] || [ "$PHP_VERSION" = "8.4" ] || { warn "PHP $PHP_VERSION invalid for 5.0.x, forcing 8.3"; PHP_VERSION="8.3"; } ;;
    6.0)
      case "$PHP_VERSION" in
        8.5) : ;;
        8.6) version_ge "$DDEV_VERSION" "1.25.5" \
               || die "PHP 8.6 needs DDEV >= 1.25.5 (found $DDEV_VERSION). Upgrade DDEV or use --php=8.5." ;;
        *)   warn "PHP $PHP_VERSION invalid for 6.0.x, forcing 8.5"; PHP_VERSION="8.5" ;;
      esac
      ;;
  esac
  local required_node=""
  case "$PRODUCT_VERSION" in
    ~6.0.*|v6.0.*|6.0.*) required_node="24" ;;
    # Exact tagged releases 5.0.0 - 5.0.10 still work with Node 22
    v5.0.[0-9]|5.0.[0-9]|v5.0.10|5.0.10) required_node="22" ;;
    # From 5.0.11 on Node 24 is required (also covers ~5.0.0 and ~5.0.x-dev)
    *5.0.*) required_node="24" ;;
  esac
  if [ -n "$required_node" ] && [ "$NODE_VERSION" != "$required_node" ]; then
    warn "Node forced to $required_node for $PRODUCT_VERSION"
    NODE_VERSION="$required_node"
  fi
  case "$DATABASE" in
    mariadb) [ "$PRODUCT_BRANCH" = "5.0" ] && DATABASE_VERSION="10.11" ;;
    mysql)   [ "$PRODUCT_BRANCH" = "5.0" ] && DATABASE_VERSION="8.4" ;;
    postgres) : ;;
    *) die "Unknown --database=$DATABASE (want mariadb|mysql|postgres)" ;;
  esac

  local allowed_search
  if [ "$DXP_EDITION" = "oss" ]; then
    allowed_search="legacy solr"
  elif [[ "$PRODUCT_BRANCH" =~ ^(4\.6|5\.0|6\.0)$ ]]; then
    allowed_search="legacy elasticsearch elasticsearch8 solr"
  else
    allowed_search="legacy elasticsearch solr"
  fi
  [[ " $allowed_search " == *" $SEARCH_ENGINE "* ]] || die "--search-engine=$SEARCH_ENGINE not valid for edition=$DXP_EDITION branch=$PRODUCT_BRANCH (allowed: $allowed_search)"

  if [ "$DXP_EDITION" = "oss" ]; then
    INSTALL_SAMPLE_DATA="false"
  elif [ "$PRODUCT_BRANCH" = "5.0" ] && [ "$IS_DEV" = "false" ]; then
    INSTALL_SAMPLE_DATA="false"
  fi

  if [ "$PRODUCT_BRANCH" = "5.0" ]; then CLOUD_CONFIG="upsun"; else CLOUD_CONFIG="platformsh"; fi

  [ "$APP_ENV" = "dev" ] && APP_DEBUG="1" || APP_DEBUG="0"

  if [ "$HTTP_SERVER" = "apache-fpm" ]; then
    warn "apache-fpm is barely tested upstream — nginx-fpm is recommended."
  fi
  if [ "$APP_CACHE" = "memcached" ]; then
    warn "memcached is barely tested upstream."
  fi
}

# ---------------------------------------------------------------------------
# Phase 3 — Persist configuration
# ---------------------------------------------------------------------------

phase3_persist_settings() {
  mkdir -p .ddev
  cat > "$SETTINGS_FILE" <<EOF
declare -- DXP_EDITION="$DXP_EDITION"
declare -- PRODUCT_TYPE="$PRODUCT_TYPE"
declare -- PRODUCT_VERSION="$PRODUCT_VERSION"
declare -- PRODUCT_BRANCH="$PRODUCT_BRANCH"
declare -- PHP_VERSION="$PHP_VERSION"
declare -- NODE_VERSION="$NODE_VERSION"
declare -- DATABASE="$DATABASE"
declare -- DATABASE_VERSION="$DATABASE_VERSION"
declare -- HTTP_CACHE="$HTTP_CACHE"
declare -- APP_CACHE="$APP_CACHE"
declare -- SEARCH_ENGINE="$SEARCH_ENGINE"
declare -- INSTALL_SAMPLE_DATA="$INSTALL_SAMPLE_DATA"
declare -- INSTALL_PROFILER="$INSTALL_PROFILER"
declare -- APP_ENV="$APP_ENV"
declare -- HTTP_SERVER="$HTTP_SERVER"
declare -- INSTALL_CLOUD_CONFIG="$INSTALL_CLOUD_CONFIG"
declare -- CLOUD_CONFIG="$CLOUD_CONFIG"
declare -- PROJECT_NAME="$PROJECT_NAME"
declare -- INITIAL_BRANCH="$INITIAL_BRANCH"
declare -- EXISTING_PROJECT="$EXISTING_PROJECT"
EOF
  log "Wrote $SETTINGS_FILE"
}

# ---------------------------------------------------------------------------
# Phase 4a — General DDEV provisioning
# ---------------------------------------------------------------------------

GENERAL_MARKER=".ddev/.ibexa-setup-general-provisioned"

phase4a_general() {
  marker_done "$GENERAL_MARKER" && { log "4a already provisioned, skipping."; return; }

  [ -d .ddev ] || ddev config --project-type=php
  ddev config --project-name="$PROJECT_NAME"

  cat > .ddev/config.ibexa.yaml <<'EOF'
#ddev-generated
docroot: public
web_environment:
    - MAILER_DSN=smtp://localhost:1025
EOF

  cat > .ddev/config.php.yaml <<EOF
#ddev-generated
php_version: "$PHP_VERSION"
EOF
  if [ "$PHP_VERSION" = "8.6" ]; then
    # Many packages do not declare PHP 8.6 support yet - ignore upper PHP
    # bounds (lower bounds are still enforced).
    cat >> .ddev/config.php.yaml <<'EOF'
web_environment:
    - COMPOSER_IGNORE_PLATFORM_REQ=php+
EOF
    log "Composer configured to ignore upper PHP version constraints (COMPOSER_IGNORE_PLATFORM_REQ=php+)"
  fi

  cat > .ddev/config.node.yaml <<EOF
#ddev-generated
nodejs_version: "$NODE_VERSION"
EOF

  cat > .ddev/config.db.yaml <<EOF
#ddev-generated
database:
    type: $DATABASE
    version: "$DATABASE_VERSION"
EOF

  if [ "$HTTP_SERVER" = "apache-fpm" ]; then
    cat > .ddev/config.http.yaml <<'EOF'
#ddev-generated
webserver_type: apache-fpm
EOF
  fi

  if [ ! -d public ]; then
    mkdir -p public
    touch public/index.html public/DELETE_PUBLIC
  fi

  {
    echo "APP_ENV=$APP_ENV"
    echo "APP_DEBUG=$APP_DEBUG"
  } >> .env.local

  mark "$GENERAL_MARKER"
  log "Restarting DDEV to pick up PHP/webserver/database config..."
  ddev restart -y
}

# ---------------------------------------------------------------------------
# Phase 4b — Services provisioning
# ---------------------------------------------------------------------------

SERVICES_MARKER=".ddev/.ibexa-setup-services-provisioned"

APACHE_VHOST_FALLBACK() {
  cat <<'EOF'
<VirtualHost %IP_ADDRESS%:%PORT%>
    ServerName %HOST_NAME%
    ServerAlias %HOST_ALIAS%
    DocumentRoot %BASEDIR%/public
    DirectoryIndex index.php
    SetEnvIf X-Forwarded-Proto "https" HTTPS=on
    LimitRequestBody %BODY_SIZE_LIMIT%
    TimeOut %TIMEOUT%
    <Directory %BASEDIR%/public>
        <FilesMatch \.php$>
            SetHandler "proxy:%FASTCGI_PASS%|fcgi://localhost/"
        </FilesMatch>
        Options FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        RewriteRule ^var/.*(?i)\.(php3?|phar|phtml|sh|exe|pl|bin)$ - [F]
        RewriteRule ^/favicon\.ico - [L]
        RewriteRule ^/robots\.txt - [L]
        RewriteRule ^/bundles/ - [L]
        RewriteRule ^/assets/ - [L]
        RewriteRule ^/build/ - [L]
        RewriteRule ^/([^/]+/)*?index\.php([/?#]|$) - [R=404,L]
        RewriteRule .* /index.php
    </IfModule>
</VirtualHost>
EOF
}

setup_apache_vhost() {
  mkdir -p .ddev/apache
  if ! curl -fsSL "https://raw.githubusercontent.com/ibexa/post-install/$PRODUCT_BRANCH/resources/templates/apache2/vhost.template" -o .ddev/apache/apache-site.conf; then
    warn "Could not fetch upstream Apache vhost template, using bundled fallback."
    APACHE_VHOST_FALLBACK > .ddev/apache/apache-site.conf
  fi
  sed -i \
    -e "s/%HOST_NAME%/${PROJECT_NAME}.ddev.site/g" \
    -e "s/%HOST_ALIAS%/*.ddev.site/g" \
    -e "s/%IP_ADDRESS%/*/g" \
    -e "s/%PORT%/80/g" \
    -e "s#%BASEDIR%#/var/www/html#g" \
    -e "s/%BODY_SIZE_LIMIT%/0/g" \
    -e "s/%TIMEOUT%/0/g" \
    -e "s#%FASTCGI_PASS%#unix:/var/run/php-fpm.sock#g" \
    .ddev/apache/apache-site.conf
}

setup_varnish() {
  ddev dotenv set .ddev/.env.varnish --varnish-docker-image=varnish:7.1
  ddev add-on get ddev/ddev-varnish
  mkdir -p .ddev/varnish
  local base="https://raw.githubusercontent.com/ibexa/http-cache/$PRODUCT_BRANCH/docs/varnish/vcl"
  curl -fsSL "$base/parameters.vcl" -o .ddev/varnish/parameters.vcl || warn "Could not fetch parameters.vcl"
  curl -fsSL "$base/varnish7.vcl" -o .ddev/varnish/default.vcl || warn "Could not fetch varnish7.vcl"

  cat > .ddev/config.varnish.yaml <<'EOF'
#ddev-generated
web_environment:
    - TRUSTED_PROXIES=varnish
    - HTTPCACHE_PURGE_TYPE=varnish
    - HTTPCACHE_PURGE_SERVER=http://varnish
EOF

  if [ -f .ddev/varnish/parameters.vcl ]; then
    sed -i \
      -e 's/127\.0\.0\.1/web/g' \
      -e 's/acl invalidators {/acl invalidators +log {\n    "web";/' \
      -e 's/acl debuggers {/acl debuggers +log {\n    "0.0.0.0"\/0;/' \
      .ddev/varnish/parameters.vcl
  fi
}

setup_memcached() {
  { echo 'CACHE_POOL="cache.memcached"'; echo 'CACHE_DSN="memcached:11211?weight=33"'; } >> .env.local
  ddev add-on get ddev/ddev-memcached
}

setup_redis_valkey() {
  if [ "$APP_CACHE" = "valkey" ]; then
    ddev dotenv set .ddev/.env.redis --redis-docker-image=valkey/valkey:9.1
  fi
  ddev dotenv set .env.local --cache-pool=cache.redis
  ddev dotenv set .env.local --cache-dsn=redis:6379
  ddev add-on get ddev/ddev-redis
  mkdir -p .ddev/redis
  cat > .ddev/redis/redis.conf <<'EOF'
maxmemory 2048mb
maxmemory-policy volatile-lfu
EOF
}

setup_solr() {
  { echo 'SOLR_CORE=collection1'; echo 'SOLR_DSN=http://solr:8983/solr'; } >> .env.local
  ddev add-on get ddev/ddev-solr
  ddev dotenv set .ddev/.env.solr --solr-opts="-Dsolr.autoSoftCommit.maxTime=20"
}

setup_elasticsearch() {
  { echo 'SEARCH_ENGINE=elasticsearch'; echo 'ELASTICSEARCH_DSN=http://elasticsearch:9200'; } >> .env.local
  ddev add-on get ddev/ddev-elasticsearch
  if [ "$SEARCH_ENGINE" = "elasticsearch8" ] || [[ "$PRODUCT_BRANCH" =~ ^(5\.0|6\.0)$ ]]; then
    cp .ddev/elasticsearch/docker-compose.elasticsearch8.yaml .ddev/
    ddev dotenv set .ddev/.env.elasticsearch --elasticsearch-docker-image=elasticsearch:8.19.0
    ES_MAJOR="8"
  else
    cp .ddev/elasticsearch/docker-compose.elasticsearch7.yaml .ddev/
    ddev dotenv set .ddev/.env.elasticsearch --elasticsearch-docker-image=elasticsearch:7.17.14
    ES_MAJOR="7"
  fi
}

phase4b_services() {
  marker_done "$SERVICES_MARKER" && { log "4b already provisioned, skipping."; return; }

  ddev dotenv set .ddev/.env --dxp-release="$PRODUCT_VERSION"
  ddev dotenv set .env.local --app-secret="$(openssl rand -hex 32)"

  local scheme port charset collation db_version
  case "$DATABASE" in
    mariadb|mysql) scheme="mysql"; port="3306"; charset="utf8mb4"; collation="utf8mb4_unicode_520_ci" ;;
    postgres)      scheme="postgresql"; port="5432"; charset="utf8"; collation="utf8_unicode_ci" ;;
  esac

  if [ "$DATABASE" = "mariadb" ]; then
    db_version="mariadb-$(ddev exec -s db mysql -V | awk '{print $5}' | sed 's/-.*//')"
  else
    db_version="$DATABASE_VERSION"
  fi

  {
    echo "DATABASE_URL=${scheme}://db:db@db:${port}/db?serverVersion=${db_version}&charset=${charset}"
    echo "DATABASE_VERSION=${db_version}"
    echo "DATABASE_CHARSET=${charset}"
    echo "DATABASE_COLLATION=${collation}"
  } >> .env.local

  [ "$HTTP_SERVER" = "apache-fpm" ] && setup_apache_vhost
  [ "$HTTP_CACHE" = "varnish" ] && setup_varnish
  [ "$APP_CACHE" = "memcached" ] && setup_memcached
  { [ "$APP_CACHE" = "redis" ] || [ "$APP_CACHE" = "valkey" ]; } && setup_redis_valkey
  [ "$SEARCH_ENGINE" = "solr" ] && setup_solr
  [[ "$SEARCH_ENGINE" == elasticsearch* ]] && setup_elasticsearch

  mark "$SERVICES_MARKER"
  log "Restarting DDEV to pick up services..."
  ddev restart -y
}

# ---------------------------------------------------------------------------
# Phase 5 — Composer install
# ---------------------------------------------------------------------------

git_commit_all() {
  ddev exec git add . ':!.ddev'
  ddev exec git commit -m "$1" --allow-empty-message -q || true
}

fixtures_version() {
  case "$PRODUCT_VERSION" in
    *4.6*) echo "~4.6.x-dev" ;;
    *6.0*) echo "~6.0.x-dev" ;;
    *)     echo "~5.0.x-dev" ;;
  esac
}

install_optional_packages() {
  PACKAGES_ADDED="false"
  if [ "$INSTALL_SAMPLE_DATA" = "true" ]; then
    if ddev composer require "ibexa/test-fixtures:$(fixtures_version)" --no-scripts --no-interaction; then
      PACKAGES_ADDED="true"
    else
      warn "ibexa/test-fixtures require failed (access is restricted) — continuing without sample data."
    fi
  fi
  if [ "$INSTALL_PROFILER" = "true" ]; then
    ddev composer require --dev symfony/profiler-pack --no-scripts --no-interaction
    PACKAGES_ADDED="true"
  fi
  if [ "$INSTALL_CLOUD_CONFIG" = "true" ]; then
    if [ "$CLOUD_CONFIG" = "upsun" ]; then
      ddev composer require ibexa/cloud
      ddev php bin/console ibexa:cloud:setup --upsun
    else
      ddev composer require ibexa/cloud
      ddev composer ibexa:setup --platformsh
    fi
    PACKAGES_ADDED="true"
  fi
  [ "$PACKAGES_ADDED" = "true" ] && git_commit_all "Added packages"
}

stash_env_local() {
  if [ -f .env.local ]; then
    mv .env.local .ddev/.env.local.tmp
  elif [ ! -f .ddev/.env.local.tmp ]; then
    warn "No .env.local to stash (unexpected) — continuing without one."
  fi
}

restore_env_local() {
  [ -f .ddev/.env.local.tmp ] && mv .ddev/.env.local.tmp .env.local
}

init_git_if_needed() {
  if [ ! -d .git ]; then
    ddev exec git init -b "$INITIAL_BRANCH" -q
    git_commit_all "Installed Ibexa DXP"
  fi
}

# Each step below is guarded by the filesystem state it produces, so a run
# interrupted mid-Composer (e.g. after create-project but before git init)
# can be safely resumed without redoing completed work or hitting
# composer's "must be a clean/empty project" refusal on retry.
phase5_case3_dev_branch() {
  log "Fresh install, dev branch ($PRODUCT_VERSION) — installing via website-skeleton."
  stash_env_local

  if [ ! -f composer.json ]; then
    ddev composer create-project "ibexa/website-skeleton:$PRODUCT_VERSION"
    if [ "$DXP_EDITION" != "oss" ]; then
      ddev composer config repositories.ibexa composer https://updates.ibexa.co
    fi
    if [ "$PRODUCT_BRANCH" = "4.6" ]; then
      ddev composer config extra.runtime.error_handler \
        "\\Ibexa\\Contracts\\Core\\MVC\\Symfony\\ErrorHandler\\Php82HideDeprecationsErrorHandler"
    fi
  else
    log "composer.json already present — skipping create-project."
  fi

  if [ ! -d "vendor/ibexa/$DXP_EDITION" ]; then
    if [ "$DXP_EDITION" != "oss" ]; then
      log "Auth pre-check against updates.ibexa.co..."
      ddev composer require "ibexa/$DXP_EDITION:$PRODUCT_VERSION" -W \
        --no-scripts --no-plugins --no-install --no-interaction --quiet \
        || die "updates.ibexa.co unreachable/unauthorised. Fix Composer auth (see skill's 'Composer authentication' section) and re-run — settings are already saved."
    fi
    ddev composer require "ibexa/$DXP_EDITION:$PRODUCT_VERSION" -W --no-scripts --no-interaction
  else
    log "ibexa/$DXP_EDITION already required — skipping."
  fi

  init_git_if_needed

  ddev composer recipes:install "ibexa/$DXP_EDITION" --force --reset

  ddev exec git add . ':!.ddev'
  ddev exec 'if [ $(git diff --cached --numstat | wc -l) -ne 0 ]; then git commit -m "recipes:install"; fi'

  restore_env_local
}

phase5_case4_tagged_release() {
  log "Fresh install, tagged release ($PRODUCT_VERSION) — installing via ibexa/$DXP_EDITION-skeleton."
  stash_env_local

  if [ ! -f composer.json ]; then
    ddev composer create-project "ibexa/${DXP_EDITION}-skeleton:${PRODUCT_VERSION}" --no-install
  else
    log "composer.json already present — skipping create-project."
  fi

  local mode require_flags
  if [ "$PHP_VERSION" = "8.3" ] && [[ "$PRODUCT_BRANCH" =~ ^(4\.6|5\.0|6\.0)$ ]]; then
    mode="install"
    require_flags="--no-scripts --no-plugins --no-install --no-interaction --quiet"
  else
    mode="update"
    require_flags="--update-with-all-dependencies --no-scripts --no-plugins --no-install --no-interaction --quiet"
  fi

  if [ ! -d vendor ]; then
    if [ "$DXP_EDITION" != "oss" ]; then
      log "Auth pre-check against updates.ibexa.co..."
      # shellcheck disable=SC2086
      ddev composer require "ibexa/$DXP_EDITION:$PRODUCT_VERSION" $require_flags \
        || die "updates.ibexa.co unreachable/unauthorised. Fix Composer auth (see skill's 'Composer authentication' section) and re-run — settings are already saved."
    fi
    ddev composer "$mode" --optimize-autoloader
  else
    log "vendor/ already present — skipping composer $mode."
  fi

  init_git_if_needed
  restore_env_local
}

phase5_composer_install() {
  ddev exec git config --global --add safe.directory /var/www/html
  if [ -f public/DELETE_PUBLIC ]; then
    rm -rf public
  fi

  # EXISTING_PROJECT was decided once, before this script touched anything,
  # and is persisted — re-deriving it from live vendor/composer.lock state on
  # a resumed run would misfire once a fresh install's own Composer work is
  # partway done (vendor/ exists mid-case-3/4, but the case isn't finished).
  if [ "$EXISTING_PROJECT" = "true" ]; then
    if [ -d vendor ]; then
      log "vendor/ present — nothing to install (Case 1)."
    else
      log "composer.lock present, no vendor/ — running composer install (Case 2)."
      if [ "$APP_ENV" = "prod" ]; then
        ddev composer install --no-dev --optimize-autoloader
      else
        ddev composer install --optimize-autoloader
      fi
    fi
    REQUIRE="NONE"
    return
  fi

  REQUIRE="EDITION"
  if [ "$IS_DEV" = "true" ]; then
    phase5_case3_dev_branch
  else
    phase5_case4_tagged_release
  fi
  install_optional_packages
}

# ---------------------------------------------------------------------------
# Phase 6 — Application setup
# ---------------------------------------------------------------------------

phase6_app_setup() {
  if [ "$IS_DEV" = "true" ] && [ "$REQUIRE" != "NONE" ]; then
    ddev composer run post-update-cmd
  fi

  ddev php bin/console ibexa:install --quiet --no-debug --skip-indexing --no-interaction

  if [ "$IS_DEV" = "true" ] && [ "$REQUIRE" != "NONE" ]; then
    ddev php bin/console cache:clear
    [ "$APP_CACHE" = "redis" ] && ddev php bin/console cache:pool:clear cache.redis
  fi

  if [[ "$SEARCH_ENGINE" == elasticsearch* ]]; then
    if [ "$PRODUCT_BRANCH" = "4.6" ] && [ "${ES_MAJOR:-}" = "8" ]; then
      ddev composer require ibexa/elasticsearch8 --with-all-dependencies
    fi
    ddev exec curl -XDELETE 'elasticsearch:9200/*'
    ddev php bin/console ibexa:elasticsearch:put-index-template
  fi

  if [ "$SEARCH_ENGINE" = "solr" ]; then
    mkdir -p .ddev/solr/configsets/collection1
    chmod 777 .ddev/solr/configsets/collection1
    cp -R vendor/ibexa/solr/src/lib/Resources/config/solr/* .ddev/solr/configsets/collection1/
    ddev exec -s solr cp -R /opt/solr/server/solr/configsets/_default/conf/{solrconfig.xml,stopwords.txt,synonyms.txt} \
      /mnt/ddev_config/solr/configsets/collection1/
    ddev solr-zk upconfig -n collection1 -d /mnt/ddev_config/solr/configsets/collection1 -z localhost:9983
    ddev exec -s solr solr create -c collection1 -n collection1 -shards 1 -replicationFactor 1
    echo "SEARCH_ENGINE=solr" >> .env.local
  fi

  ddev php bin/console ibexa:reindex

  if [ "$INSTALL_SAMPLE_DATA" = "true" ]; then
    ddev php bin/console ibexa:test-fixtures:setup --quiet || warn "Sample data setup failed — continuing without it."
  fi

  ddev php bin/console ibexa:graphql:generate-schema

  if [ "$REQUIRE" = "NONE" ]; then
    ddev composer run post-update-cmd
  fi

  mark .ddev/.ibexa-dxp-installed
}

# ---------------------------------------------------------------------------
# Phase 7 — Report
# ---------------------------------------------------------------------------

show_report() {
  echo
  log "Ibexa DXP is ready."
  if command -v jq >/dev/null 2>&1; then
    local url
    url="$(ddev describe -j 2>/dev/null | jq -r '.raw.primary_url // empty')"
    [ -n "$url" ] && echo "  Site:      $url"
    [ -n "$url" ] && echo "  Back office: $url/admin"
  else
    ddev describe || true
  fi
  echo "  Admin login: admin / publish"
  echo
  echo "  ddev mailpit      — view caught outgoing e-mail"
  echo "  ddev xdebug on|off"
  echo "  ddev composer ...  ddev php ..."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  preflight_ddev
  preflight_workdir

  if [ -f "$SETTINGS_FILE" ]; then
    log "Resuming from $SETTINGS_FILE"
    # shellcheck disable=SC1090
    source "$SETTINGS_FILE"
  fi
  check_already_installed

  derive_product_branch
  product_type_for_edition
  detect_cloud_presets
  force_matrix_values

  preflight_composer_auth

  phase3_persist_settings
  phase4a_general
  phase4b_services
  phase5_composer_install
  phase6_app_setup
  show_report
}

main "$@"
