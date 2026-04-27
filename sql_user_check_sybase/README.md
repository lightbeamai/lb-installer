# Check permissions on Sybase ASE instance

### Pre-requisites

Install [isql](https://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.infocenter.dc36272.1572/html/commands/commands89.htm) (part of Sybase Open Client) on the machine.

The script is designed to run with the LightBeam minimal-permissions Sybase
ASE user (login + `sp_adduser` to the target database + `GRANT SELECT` on
all user tables and views in that database). The full-metadata queries
mirror the production Sybase metadata extractor in
`python-utils/structured_data/structured_data_utils/consts.py`
(`SYBASE_METADATA_EXTRACTOR_SQL` for tables, `SYBASE_VIEWS_EXTRACTOR_SQL`
for views) so a successful run here implies the production scanner will
work with the same credentials.

The script must be run **once per database** the user has been added to.
The database-list query relies on the default `guest` user in `master` for
read access to `master..sysdatabases` / `master..sysusages` — the same
mechanism the production scanner uses.

### Run the script

Specify the following options to run the script

* HOSTNAME: Hostname or IP of the Sybase ASE server.
* PORT: Port number of the Sybase ASE server (default: 5000).
* USERNAME: Username to use for connecting to the instance.
* DATABASE_NAME: Name of the database to connect to. The user must have been
  added to this database via `sp_adduser`.
* OUTPUT_FILE_PATH: Path to an output file to store the output of the script.
* Password: The script will prompt for password.

stats Mode:
```shell
./database_stats.sh -h <HOSTNAME> -p <PORT> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH>
```

full_metadata Mode:
```shell
./database_stats.sh -h <HOSTNAME> -p <PORT> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -m full_metadata
```

### Provision the scanner user (optional)

`grant_permissions.sh` automates the per-database `sp_addlogin` / `sp_adduser`
/ `GRANT SELECT` steps from the customer onboarding doc. It must be run by
an admin login with `sa_role` / `sso_role`. The script is idempotent.

* HOSTNAME: Hostname or IP of the Sybase ASE server.
* PORT: Port number (default: 5000).
* ADMIN_USER: Existing admin login (e.g. `sa`).
* NEW_USER: Login to create for LightBeam.
* DATABASES: `-d <DB1,DB2,...>` for specific databases, or `-a` for all user
  databases.
* Passwords: The script prompts for the admin password and the password to
  set on the new user.

Specific databases:
```shell
./grant_permissions.sh -h <HOSTNAME> -p <PORT> -u <ADMIN_USER> -n <NEW_USER> -d <DB1,DB2,...>
```

All user databases:
```shell
./grant_permissions.sh -h <HOSTNAME> -p <PORT> -u <ADMIN_USER> -n <NEW_USER> -a
```
