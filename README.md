# ibexa-ddev-toolkit

## Install ddev:
--> https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/


## Main usage:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ddev-dxp-installer.sh <product> <version> <installation-directory>  │
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
