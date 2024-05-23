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
│ Usage:                                                         │
│ ddev-dxp-installer.sh <project-directory>
│ <project-directory>: install directory and ddev project id          |
│ │                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Add services to existing instance (run in <project-directory>)      │
│ ../ddev-dxp-installer.sh add_redis                                  │
│ ../ddev-dxp-installer.sh add_elastic                                │
│ ../ddev-dxp-installer.sh add_varnish                                │
│ ../ddev-dxp-installer.sh add_solr                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

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
*)
  ;;
esac


# fallbacks
release=~4.6
database_type=mariadb
database_version=10.6
php_version=8.1
require_profiler=1
add_solr=0
add_varnish=0
add_redis=0
add_elastic=0

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

mkdir $1
cd $1

serverVersion="$database_type-$database_version"
database="$database_type:$database_version"

ddev config --database="$database" --project-type=php --docroot=public --create-docroot --php-version "$php_version"
ddev start

ddev composer create -y ibexa/experience-skeleton:$release

ddev composer require --dev symfony/profiler-pack

git init; git add . > /dev/null; git commit -m "init" > /dev/null;

echo "DATABASE_URL=mysql://root:root@db:3306/experience-perso?$serverVersion&charset=utf8mb4" > .env.local

ddev php bin/console ibexa:install

echo "Preparing Ibexa personalization data..."
cp -r $SCRIPT_DIR/PersoMigrations/* src/Migrations/Ibexa/
ddev php bin/console ibexa:migrations:migrate

echo "Applying patches for Ibexa personalization"
mkdir patch
cp -r $SCRIPT_DIR/patch/* patch/
patch -p1 -i patch/personalization.patch

ddev php bin/console ibexa:graphql:generate-schema
ddev composer run post-install-cmd


# add components
if [ "$add_elastic" -eq "1" ]
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

echo "#############     Done!     ###########################"
echo "Switch to $PWD and run 'ddev launch' to open the project in your browser !"
echo "#######################################################"
