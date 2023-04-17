#! /bin/bash

# Install ddev:
# --> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/
#
# Add composer auth.json to ddev:
# mkdir -p ~/.ddev/homeadditions/.composer \
# ln -s ~/.composer/auth.json ~/.ddev/homeadditions/.composer/auth.json
#

set -e

if [ $# -eq 0 ]
  then
    echo "┌─────────────────────────────────────────────────────────────────────┐"
    echo "│ Main usage:                                                         │"
    echo "│ ddev-dxp-installer.sh <product> <version> <installation-directory>  │"
    echo "│ --> creates Ibexa DXP instance running as ddev project              │"
    echo "│ --> can be reached at https://<installation-directory>.ddev.site    │"
    echo "├─────────────────────────────────────────────────────────────────────┤"
    echo "│                                                                     │"
    echo "│ Add services (run in <installation-directory>) :                    │"
    echo "│ ../ddev-dxp-installer.sh add-redis                                  │"
    echo "│ ../ddev-dxp-installer.sh add-elastic                                │"
    echo "│ ../ddev-dxp-installer.sh add-varnish                                │"
    echo "│                                                                     │"
    echo "└─────────────────────────────────────────────────────────────────────┘"
    exit 1
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

add-varnish() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "TRUSTED_PROXIES=REMOTE_ADDR" >> .env.local
  echo "HTTPCACHE_PURGE_TYPE=varnish" >> .env.local
  name=$(basename "$(dirname "$PWD/foo.bar")")
  echo "HTTPCACHE_PURGE_SERVER=http://$name.ddev.site" >> .env.local
  
  ddev get reithor/ddev-varnish
  ddev restart
  echo "add-varnish"
  exit
}

add-redis() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "CACHE_POOL=cache.redis" >> .env.local
  echo "CACHE_DSN=redis:6379" >> .env.local
  
  ddev get ddev/ddev-redis
  echo "# dxp-installer generated"
  echo "maxmemory 9536870912" > .ddev/redis/redis.conf
  echo "maxmemory-policy volatile-lfu" >> .ddev/redis/redis.conf
  
  ddev restart
  ddev php bin/console cache:clear
  exit
}

add-elastic() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "SEARCH_ENGINE=elasticsearch" >> .env.local
  echo "ELASTICSEARCH_DSN=http://elasticsearch:9200" >> .env.local
  
  ddev get ddev/ddev-elasticsearch
  ddev restart
  ddev php bin/console ibexa:elasticsearch:put-index-template
  ddev php bin/console ibexa:reindex
  ddev php bin/console cache:clear
  exit
}

if [ $# -eq 1 ]
  then
  case $1 in
  add-varnish | add-redis | add-elastic )
    res=$(pre_check)
    if [[ ! -z "$res" ]]
      then
        eval "$1"
    fi
    exit
    ;;
  
  *)
    echo -n "unknown"
    exit
    ;;
  esac
fi

composer create ibexa/$1-skeleton $3 $2 --no-install 
cd $3

ddev config --docroot=public --database=mariadb:10.4
ddev start
ddev composer update
ddev composer require --dev symfony/profiler-pack

git init; git add . > /dev/null; git commit -m "init" > /dev/null;

read -p "Database name [$1]: " dbname
dbname=${dbname:-$1}
echo "DATABASE_URL=mysql://root:root@db:3306/$dbname?serverVersion=mariadb-10.4.14&charset=utf8mb4" > .env.local

ddev php bin/console ibexa:install
ddev php bin/console ibexa:graphql:generate-schema

ddev composer run post-install-cmd

echo "Done."