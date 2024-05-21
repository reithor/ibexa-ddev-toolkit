# ibexa-ddev-toolkit

Kick starter to create a clean Ibexa DXP project using ddev.

## Needed:

### ddev installed on your computer
  (https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/)

### When your are already using Composer:
(and have `~/.composer/auth.json`)
```
# Add composer auth.json to ddev:
# mkdir -p ~/.ddev/homeadditions/.composer \
# ln -s ~/.composer/auth.json ~/.ddev/homeadditions/.composer/auth.json

```

## Usage:

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                         │
│ ddev-dxp-installer.sh <project-directory>                          │
│ <project-directory>: install directory and ddev project id          |
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Add services to existing instance (run in <project-directory>)      │
│ ../ddev-dxp-installer.sh add_redis                                  │
│ ../ddev-dxp-installer.sh add_elastic                                │
│ ../ddev-dxp-installer.sh add_varnish                                │
│ ../ddev-dxp-installer.sh add_solr                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

```


