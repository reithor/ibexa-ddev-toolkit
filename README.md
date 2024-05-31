# Personalization Training



## Needed for the training:

1. Installed Ibexa Experience v4.6.6 with added migrations from `PersoMigrations` directory and applied patch `patch/personalization.patch` 
2. Your installation needs a publicly available URL

## 1. Ibexa Experience v4.6.6 + PersoMigrations

### When using ddev:

Just run `ddev-dxp-installer.sh /[your-prefered-directory]/perso-training`
This will install Ibexa DXP, apply patch and run PersoMigrations.
Project URL will be: https://perso-training.ddev.site/

### When not using ddev:

1.1 Install Ibexa Experience v4.6.6 

1.2 Copy `patch patch/personalization.patch` to your project and run `patch -p1 -i patch/personalization.patch`

1.3 Copy subdirectories from `PersoMigrations` to `src/Migrations/Ibexa/` and run `php bin/console ibexa:migrations:migrate`


## 2. Make your project 'public'

### Use ngrock:

-> https://ngrok.com/docs/getting-started/ - Step 1, Step 2 and Step 4(!)

Assuming that Ibexa DXP is running on port `8080`:<br>
Run `ngrok http 8080 --domain [your-fixed-subdomain].ngrok-free.app`

With ddev:<br>
Run `ddev share --ngrok-args "--domain [your-fixed-subdomain].ngrok-free.app"``

--------------

## For ddev:

### installed on your computer
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
│                                                                     │
│ ddev-dxp-installer.sh <project-directory>                           │
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


