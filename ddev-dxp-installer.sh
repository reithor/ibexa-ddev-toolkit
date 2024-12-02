#! /bin/bash

# Install ddev:
# --> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/
#
# Add composer auth.json to ddev:
# mkdir -p ~/.ddev/homeadditions/.composer \
# ln -s ~/.composer/auth.json ~/.ddev/homeadditions/.composer/auth.json
#

set -e

__help="
┌─────────────────────────────────────────────────────────────────────┐
│ Main usage:                                                         │
│ ddev-dxp-installer.sh <product> <project-directory> <config-file>   │
│ <product>: content | headless | experience | commerce               │
│ <project-directory>: install directory and ddev project id          |
│ <config-file> (optional) : config options                           |
│ --> reads settings from default.config                              │
│ --> asks for confirmation for every single option (list see below)  │
│ --> creates Ibexa DXP instance running as ddev project              │
│ --> can be reached at https://<installation-directory>.ddev.site    │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Add services to existing instance (run in <project-directory>)      │
│ ../ddev-dxp-installer.sh add_redis                                  │
│ ../ddev-dxp-installer.sh add_elastic                                │
│ ../ddev-dxp-installer.sh add_varnish                                │
│ ../ddev-dxp-installer.sh add_solr                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

# default config
release: ~4.6       # latest 4.x
database_type=mariadb # db settings
database_version=10.6
php_version=8.3     # php
require_profiler=1  # require symfony/profiler-pack
add_solr=0          # add solr search 
add_varnish=0       # add varnish http cache 
add_redis=0         # add redis persistence cache 
add_elastic=0       # add elastic search

"

help()
{
  echo "$__help"
  exit 1
}

if [ $# -eq 0 ]
  then
    help
fi


pre_check()
{
   has_ddev=$(find .  -maxdepth 1 -name ".ddev")
   if [ -z "$has_ddev" ]
   then
    exit 0
   else
    echo 1
   fi
}

add_solr() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "SEARCH_ENGINE=solr" >> .env.local
  echo "SOLR_CORE=collection1" >> .env.local
  echo "SOLR_DSN=http://solr:8983/solr" >> .env.local
  ddev get reithor/ddev-ibexa-solr
  ddev restart
  ddev php bin/console ibexa:reindex
}

add_varnish() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "TRUSTED_PROXIES=REMOTE_ADDR" >> .env.local
  echo "HTTPCACHE_PURGE_TYPE=varnish" >> .env.local
  name=$(basename "$(dirname "$PWD/foo.bar")")
  echo "HTTPCACHE_PURGE_SERVER=http://$name.ddev.site" >> .env.local
  
  ddev get reithor/ddev-varnish
  ddev restart
}

add_redis() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "CACHE_POOL=cache.redis" >> .env.local
  echo "CACHE_DSN=redis:6379" >> .env.local
  
  ddev get ddev/ddev-redis
  echo "# dxp-installer generated" > .ddev/redis/redis.conf
  echo "maxmemory 9536870912" >> .ddev/redis/redis.conf
  echo "maxmemory-policy volatile-lfu" >> .ddev/redis/redis.conf
  
  ddev restart
  ddev php bin/console cache:clear
}

add_elastic() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "SEARCH_ENGINE=elasticsearch" >> .env.local
  echo "ELASTICSEARCH_DSN=http://elasticsearch:9200" >> .env.local
  
  ddev get ddev/ddev-elasticsearch
  ddev restart
  ddev php bin/console ibexa:elasticsearch:put-index-template
  ddev php bin/console ibexa:reindex
  ddev php bin/console cache:clear
}

# check arguments
case $1 in
# add functionality to existing install
add_varnish | add_redis | add_elastic | add_solr )
  res=$(pre_check)
  if [[ ! -z "$res" ]]
    then
      eval "$1"
      exit
  fi
  exit
  ;;
# initialize
oss | content | headless | experience | commerce )
  if [ $# -eq 1 ]
    then
    echo "+++++ Target Directory Is Required +++++"
    exit;
  fi
  ;;
*)
  echo "+++++ Unknown Option +++++"
  help
  exit
  ;;
esac

if [ $# -eq 3 ]
  then
    config_file="$3"
  else
    config_file="$( dirname -- "$0"; )/default.config"
fi

# fallbacks
release=~4.6
database_type=mariadb
database_version=10.6
php_version=8.3
require_profiler=1
add_solr=0
add_varnish=0
add_redis=0
add_elastic=0

if [ -f "$config_file" ]
  then
    # use config file if present
    # fallbacks will be overwritten !
    . $config_file
fi

read -p "release [$release]: " release_input
release=${release_input:=$release}

read -p "database_type [$database_type]: " database_type_input
database_type=${database_type_input:=$database_type}

read -p "database_version [$database_version]: " database_version_input
database_version=${database_version_input:=$database_version}

read -p "php_version [$php_version]: " php_version_input
php_version=${php_version_input:=$php_version}

read -p "require_profiler [$require_profiler]: " require_profiler_input
require_profiler=${require_profiler_input:=$require_profiler}

read -p "add_solr [$add_solr]: " add_solr_input
add_solr=${add_solr_input:=$add_solr}

read -p "add_varnish [$add_varnish]: " add_varnish_input
add_varnish=${add_varnish_input:=$add_varnish}

read -p "add_redis [$add_redis]: " add_redis_input
add_redis=${add_redis_input:=$add_redis}

read -p "add_elastic [$add_elastic]: " add_elastic_input
add_elastic=${add_elastic_input:=$add_elastic}

mkdir $2
cd $2

serverVersion="$database_type-$database_version"
database="$database_type:$database_version"

ddev config --database="$database" --project-type=php --docroot=public --create-docroot --php-version "$php_version"
ddev start

flavor=$1
if [[ "$1" = "headless" ]] && ! [[ "$release" =~ .*"4.6".* ]]; then
  flavor="content"
fi

if [[ "$1" = "content" ]] &&  [[ "$release" =~ .*"4.6".* ]]; then
  flavor="headless"
fi

ddev composer create -y ibexa/$flavor-skeleton:$release --no-install

if [[ "$php_version" = "8.3" && "$release" =~ .*"4.6".*  ]]
  then
    ddev composer install
  else
    ddev composer update
fi

if [ "$require_profiler" = "1" ]
  then
    ddev composer require --dev symfony/profiler-pack
fi

git init; git add . > /dev/null; git commit -m "init" > /dev/null;

dbname=$flavor
if [ "$database_type" = "postgres" ]
then
    echo "DATABASE_URL=postgresql://db:db@db:5432/$dbname" > .env.local
  else
    echo "DATABASE_URL=mysql://root:root@db:3306/$dbname?$serverVersion&charset=utf8mb4" > .env.local
fi

ddev php bin/console ibexa:install
ddev php bin/console ibexa:graphql:generate-schema
ddev composer run post-install-cmd


# add components
if [ "$add_elastic" -eq "1" ] && [ "$1" != "oss" ]
  then
    echo "Adding elastic search service"
    add_elastic
fi

if [ "$add_solr" -eq "1" ]
  then
    echo "Adding solr service"
    add_solr
fi

if [ "$add_varnish" -eq "1" ]
  then
    echo "Adding varnish service"
    add_varnish
fi

if [ "$add_redis" -eq "1" ]
  then
    echo "Adding redis service"
    add_redis
fi


echo "Done."
