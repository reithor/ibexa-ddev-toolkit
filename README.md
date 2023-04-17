# ibexa-ddev-toolkit

## Install ddev:
--> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/


## Main usage:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Main usage:                                                         │
│ ddev-dxp-installer.sh <product> <version> <directory> <config-file> │
│ <product>: content | experience | commerce                          │
│ <version>: composer version constraint (^3.3 -> latest 3.3)         |
│ <directory>: install directory and ddev project id                  |
│ <config-file> (optional) : config options                           |
│ --> creates Ibexa DXP instance running as ddev project              │
│ --> can be reached at https://<installation-directory>.ddev.site    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Add services (run in <installation-directory>) :                    │
│ ../ddev-dxp-installer.sh add-redis                                  │
│ ../ddev-dxp-installer.sh add-elastic                                │
│ ../ddev-dxp-installer.sh add-varnish                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```
