#!/bin/bash
# Provisions a minimal-permissions LightBeam scanner user on a Sybase ASE
# instance, following the same three-step pattern as the customer-facing
# onboarding documentation:
#
#   1. sp_addlogin (server level)        -- runs once
#   2. sp_adduser  (per target database) -- runs for each database
#   3. GRANT SELECT on every user table and view (per target database)
#
# Sybase ASE has no wildcard / schema-level GRANT, so step 3 iterates
# sysobjects (type IN ('U','V')) via a cursor.
#
# Run this script from a workstation that has the Sybase Open Client `isql`
# utility installed, using an admin login that has sa_role / sso_role
# (e.g. 'sa') so it is allowed to call sp_addlogin / sp_adduser / GRANT.

set -e

port=5000
all_databases=false

while getopts h:p:u:n:d:a flag; do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        p) port=${OPTARG};;
        u) admin_user=${OPTARG};;
        n) new_user=${OPTARG};;
        d) databases=${OPTARG};;
        a) all_databases=true;;
    esac
done

if ! command -v isql &>/dev/null; then
    echo "isql is not installed. Install Sybase Open Client to get the isql utility." >&2
    exit 1
fi

if [ -z "$dbhost" ] || [ -z "$admin_user" ] || [ -z "$new_user" ]; then
    echo "Usage: $0 -h <HOST> -p <PORT> -u <ADMIN_USER> -n <NEW_USER> (-d <DB1,DB2,...> | -a)" >&2
    echo "  -h  Hostname or IP of the Sybase ASE server" >&2
    echo "  -p  Port number (default: 5000)" >&2
    echo "  -u  Admin username (must have sa_role / sso_role)" >&2
    echo "  -n  Username to create for LightBeam" >&2
    echo "  -d  Comma-separated list of databases to grant SELECT on" >&2
    echo "  -a  Grant SELECT on all user databases (auto-discovered from" >&2
    echo "      master..sysdatabases; system databases are excluded)" >&2
    exit 1
fi

if [ -z "$databases" ] && [ "$all_databases" = false ]; then
    echo "Specify either -d <DB1,DB2,...> or -a (all user databases)." >&2
    exit 1
fi

if [ -n "$databases" ] && [ "$all_databases" = true ]; then
    echo "-d and -a are mutually exclusive." >&2
    exit 1
fi

read -sp "Password for admin user '$admin_user': " admin_password
echo
read -sp "Password to set for new user '$new_user': " new_password
echo

if [ -z "$admin_password" ] || [ -z "$new_password" ]; then
    echo "Passwords cannot be empty." >&2
    exit 1
fi

# --- Discover all user databases when -a is set ---
if [ "$all_databases" = true ]; then
    echo "==> Enumerating user databases on $dbhost ..."
    # Exclusion list mirrors SYBASE_SKIP_DATABASES in
    # python-utils/structured_data/structured_data_utils/sybase/consts.py
    raw=$(isql -S "$dbhost" -U "$admin_user" -P "$admin_password" -w 999 <<'SQL'
set nocount on
go
SELECT '##LB##' + name + '##END##' FROM master..sysdatabases
WHERE name NOT IN ('master','tempdb','model','sybsystemprocs','sybsecurity',
                   'sybsystemdb','sybpcidb','dbccdb','sybmgmtdb','sybdiag')
ORDER BY name
go
SQL
)
    databases=$(echo "$raw" | sed -n 's/.*##LB##\(.*\)##END##.*/\1/p' | tr -d ' \r' | paste -sd ',' -)
    if [ -z "$databases" ]; then
        echo "No user databases discovered. Nothing to do." >&2
        exit 1
    fi
    echo "    Discovered: $databases"
fi

echo "dbhost: $dbhost port: $port admin_user: $admin_user new_user: $new_user databases: $databases"

# --- Step 1: create the server-level login (idempotent) ---
echo "==> Creating login '$new_user' at the server level (if missing)..."
isql -S "$dbhost" -U "$admin_user" -P "$admin_password" -w 999 <<SQL
IF NOT EXISTS (SELECT 1 FROM master..syslogins WHERE name = '$new_user')
    EXEC sp_addlogin '$new_user', '$new_password'
ELSE
    PRINT 'Login $new_user already exists, skipping sp_addlogin'
go
SQL

# --- Steps 2 & 3: per-database, add user and grant SELECT on tables + views ---
IFS=',' read -ra DB_ARRAY <<< "$databases"
for db in "${DB_ARRAY[@]}"; do
    db="$(echo "$db" | xargs)"  # trim whitespace
    if [ -z "$db" ]; then
        continue
    fi
    echo "==> Configuring database '$db'..."
    isql -S "$dbhost" -U "$admin_user" -P "$admin_password" -D "$db" -w 999 <<SQL
IF NOT EXISTS (SELECT 1 FROM sysusers WHERE name = '$new_user')
    EXEC sp_adduser '$new_user'
ELSE
    PRINT 'User $new_user already exists in $db, skipping sp_adduser'
go

IF object_id('sp_lb_grant_select') IS NOT NULL
    DROP PROCEDURE sp_lb_grant_select
go

CREATE PROCEDURE sp_lb_grant_select @username VARCHAR(100)
AS
BEGIN
    DECLARE @tname VARCHAR(256)
    DECLARE @sql VARCHAR(512)
    DECLARE cur CURSOR FOR
        SELECT name FROM sysobjects WHERE type IN ('U', 'V')
    OPEN cur
    FETCH cur INTO @tname
    WHILE @@sqlstatus = 0
    BEGIN
        SELECT @sql = 'GRANT SELECT ON ' + @tname + ' TO ' + @username
        EXEC(@sql)
        FETCH cur INTO @tname
    END
    CLOSE cur
    DEALLOCATE CURSOR cur
END
go

EXEC sp_lb_grant_select '$new_user'
go

DROP PROCEDURE sp_lb_grant_select
go
SQL
done

echo
echo "Done. Login '$new_user' is now provisioned with SELECT permissions on:"
for db in "${DB_ARRAY[@]}"; do
    db="$(echo "$db" | xargs)"
    [ -n "$db" ] && echo "  - $db"
done
echo
echo "Re-run this script (or step 3 of the doc) whenever new tables or views"
echo "are added: Sybase ASE has no concept of default privileges for future"
echo "objects."
