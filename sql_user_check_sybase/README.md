# Check permissions on Sybase ASE instance

### Pre-requisites

Install [`isql`](https://help.sap.com/docs/SAP_ASE) (part of SAP ASE / Sybase Open Client) on the machine.

### Run the script

Run the script once per database the LightBeam user has been added to.

* HOSTNAME: Hostname or IP of the Sybase ASE server.
* PORT: Port number (default: 5000).
* USERNAME: Username to use for connecting to the instance.
* DATABASE_NAME: Database to connect to.
* OUTPUT_FILE_PATH: Path to an output file to store the script output.
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
