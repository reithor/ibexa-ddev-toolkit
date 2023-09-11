# ibexa-ddev-toolkit

Kick starter to create a clean Ibexa DXP project using ddev.
It's perfectly what I need for my daily work - and will rarely be changed/improved in the future.  

## Install ddev:
--> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/


## Main usage:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Main usage:                                                         │
│ ddev-dxp-installer.sh <product> <project-directory> <config-file>   │
│ <product>: content | experience | commerce                          │
│ <project-directory>: install directory and ddev project id          |
│ <config-file> (optional) : config options (see below)               |
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
release: ~4.4       # latest 4.x
database_type=mariadb # db settings
database_version=10.6
php_version=8.1     # php
require_profiler=0  # require symfony/profiler-pack
add_solr=0          # add solr search 
add_varnish=0       # add varnish http cache 
add_redis=0         # add redis persistence cache 
add_elastic=0       # add elastic search

```


