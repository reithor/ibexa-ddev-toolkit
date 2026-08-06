## Requirements:

DDEV:
--> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/


## install-ibexa-dxp.sh

Non-Interactive installer for Ibexa DXP

```
install-ibexa-dxp.sh [options]

  --edition=oss|headless|experience|commerce   (default: experience)
  --release=VERSION      Composer constraint, e.g. ~5.0.0, ~5.0.x-dev, 5.0.3
  --php=VERSION          (default: 8.3; forced/validated per release)
  --node=VERSION         (default: 22; forced on 5.0.x/6.0.x)
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
```


Check https://github.com/reithor/ddev-ibexa-installer for an interactive installer !