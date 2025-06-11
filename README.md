# Personalization Training



## Needed for the training:

1. Installed Ibexa Experience v4.6 with added migrations from `PersoMigrations` directory
2. Your installation needs a publicly available URL

## 1. Ibexa Experience v4.6 + PersoMigrations

### When using ddev:

Just run `./ddev-dxp-installer.sh /[your-prefered-directory]/perso-training`
This will install Ibexa DXP, apply patch and run PersoMigrations.
Project URL will be: https://perso-training.ddev.site/

### When not using ddev:

1.1 Install Ibexa Experience v4.6

1.2 Copy `patch patch/personalization.patch` to your project and run `patch -p1 -i patch/personalization.patch`

1.3 Copy subdirectories from `PersoMigrations` to `src/Migrations/Ibexa/` and run:
```
php bin/console ibexa:migrations:migrate
php bin/console ibexa:graphql:generate-schema
php bin/console cache:clear
```

## 2. Make your project 'public'

### Use ngrock:

#### Install Ngrock (https://ngrok.com/docs/getting-started/ - Step 1, Step 2 and Step 4(!)

#### Step 1: Install -> run install script in linux/mac<br>
#### Step 2: Connect your account -> run `ngrok config add-authtoken <TOKEN>`  in linux/mac (Token -> https://dashboard.ngrok.com/get-started/your-authtoken)<br>
#### Step 4: Create fixed domain : https://dashboard.ngrok.com/cloud-edge/domains <br>


Assuming that Ibexa DXP is running on port `8080`:<br>
Run `ngrok http 8080 --domain [your-fixed-subdomain].ngrok-free.app`

With ddev:<br>
Run `ddev share --ngrok-args "--domain [your-fixed-subdomain].ngrok-free.app"`


## 3. Enable Personalization

#### Step 1: https://doc.ibexa.co/projects/userguide/en/4.6/personalization/enable_personalization/<br>
(you need a active Installation key for Ibexa DXP (!) )<br>
#### Step 2: Add config to `.env.local`

```
# .env.local
PERSONALIZATION_CUSTOMER_ID=...
PERSONALIZATION_LICENSE_KEY=....
PERSONALIZATION_HOST_URI=[your_ngrock_full_url]
```
#### Step 3: Add Yaml config:

```
# config/packages/app_perso.yaml
ibexa:
    system:
        default:
            personalization:
                site_name: 'My test' # For example 'ENU store'
                host_uri: '%env(PERSONALIZATION_HOST_URI)%'
                authentication:
                    customer_id: '%env(int:PERSONALIZATION_CUSTOMER_ID)%'
                    license_key: '%env(PERSONALIZATION_LICENSE_KEY)%'
                included_item_types: [laptop,mouse,pc,software,article]
                output_type_attributes:
                    54: # laptop
                        title: 'name'
                        image: 'image'
                        description: 'description'
                    56: # mouse
                        title: 'name'
                        image: 'image'
                        description: 'description'
                    55: # pc
                        title: 'name'
                        image: 'image'
                        description: 'description'
                    57: # Software
                        title: 'name'
                        image: 'image'
                        description: 'description'
                    2: # Article
                        title: 'title'
                        image: 'image'
                        description: 'short_title'
```

#### Setp 4: Start Ngrock (if not already done)

```
ddev share --ngrok-args "--domain [your-fixed-subdomain].ngrok-free.app"
```

#### Setp 5: Run Export 

```
ddev php bin/console ibexa:personalization:run-export --siteaccess=site  \
   --item-type-identifier-list=article,laptop,mouse,pc,software  \
   --customer-id=[your-customer-id]  \
   --license-key=[license-key]  \
   --languages=eng-GB
```


--------------

## For ddev first steps:

### Installation
  (https://ddev.readthedocs.io/en/latest/users/install/ddev-installation/)

### Composer auth : ( `~/.composer/auth.json` should exist)
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


