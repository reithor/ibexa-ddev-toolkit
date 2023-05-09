#! /bin/bash

# Install ddev:
# --> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/
#
# Add composer auth.json to ddev:
# mkdir -p ~/.ddev/homeadditions/.composer \
# ln -s ~/.composer/auth.json ~/.ddev/homeadditions/.composer/auth.json
#

set -e
help()
{
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│ Main usage:                                                         │"
  echo "│ ddev-dxp-installer.sh <product> <version> <directory> <config-file> │"
  echo "│ <product>: content | experience | commerce                          │"
  echo "│ <version>: composer version constraint (^3.3 -> latest 3.3)         |"
  echo "│ <directory>: install directory and ddev project id                  |"
  echo "│ <config-file> (optional) : config options                           |"
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

add-solr() {
  echo "# " >> .env.local
  echo "# dxp-installer generated" >> .env.local
  echo "SEARCH_ENGINE=solr" >> .env.local
  echo "SOLR_CORE=collection1" >> .env.local
  echo "SOLR_DSN=http://solr:8983/solr" >> .env.local
  ddev get reithor/ddev-ibexa-solr
  ddev restart
  ddev php bin/console ibexa:reindex
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
}

add-redis() {
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
}

# check arguments
case $1 in
# add functionality to existing install
add-varnish | add-redis | add-elastic | add-solr )
  res=$(pre_check)
  if [[ ! -z "$res" ]]
    then
      eval "$1"
      exit
  fi
  exit
  ;;
# initialize
oss | content | experience | commerce )
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
release=~4.3
database_type=mariadb
database_version=10.6
php_version=8.1
require_profiler=0
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
ddev composer create -y ibexa/$1-skeleton:$release

if [ "$require_profiler" = "1" ]
  then
    ddev composer require --dev symfony/profiler-pack
fi

git init; git add . > /dev/null; git commit -m "init" > /dev/null;

dbname=$1
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
    add-elastic
fi

if [ "$add_solr" -eq "1" ]
  then
    echo "Adding solr service"
    add-solr
fi

if [ "$add_varnish" -eq "1" ]
  then
    echo "Adding varnish service"
    add-varnish
fi

if [ "$add_redis" -eq "1" ]
  then
    echo "Adding redis service"
    add-redis
fi


echo "Done."