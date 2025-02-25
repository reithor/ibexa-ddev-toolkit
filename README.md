### NEW

- Installer can install ~5.0.x-dev and ~4.6.x-dev versions.
- Shortcuts for version constraints:
    - _main_ or _5.0_ ==> ~5.0.x-dev
    - _4.6_ => ~4.6.x-dev
    - _LTS_, _lts_, _latest_ => latest v4.6.xx 

# ibexa-ddev-toolkit

Kick starter to create a clean Ibexa DXP project using ddev.

## Install ddev:
--> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/


## Main usage:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Main usage:                                                         │
│ ddev-dxp-installer.sh <product> <project-directory> <config-file>   │
│ <product>: content | headless | experience | commerce               │
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
release: ~4.6       # latest 4.x
database_type=mariadb # db settings
database_version=10.6
php_version=8.3     # php
require_profiler=1  # require symfony/profiler-pack
add_solr=0          # add solr search 
add_varnish=0       # add varnish http cache 
add_redis=0         # add redis persistence cache 
add_elastic=0       # add elastic search

```


