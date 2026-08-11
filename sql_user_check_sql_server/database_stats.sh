#!/bin/bash

mode="stats"
use_ad_auth=0
trust_server_cert=0
port=""

set -e

usage() {
    cat <<'USAGE'
Usage: ./database_stats.sh -h HOST -u USER -d DATABASE -o OUTPUT_FILE [options]

Collects size and schema metadata from a SQL Server instance. Runs read-only
queries and writes the results to OUTPUT_FILE.

Required:
  -h HOST          Hostname or IP. For a named instance use HOST\INSTANCE
  -u USER          Login name
  -d DATABASE      Database to connect to (e.g. master)
  -o OUTPUT_FILE   File to write the results to

Optional:
  -p PORT          Port number (default 1433)
  -m MODE          stats (default) or full_metadata
  -a 1             Use Entra ID / Azure AD authentication
  -t 1             Trust the server certificate
  -?               Show this help

The password is read at the prompt, or taken from SQLCMDPASSWORD if that is
already set in the environment.

Example:
  ./database_stats.sh -h sql.example.com -u svc_reader -d master -o stats.txt -t 1
USAGE
}

if [ $# -eq 0 ]; then
    usage >&2
    exit 1
fi

# Handled before getopts because some shells expand an unquoted -? themselves.
case "${1}" in
    --help|-help|help)
        usage
        exit 0;;
esac

# A leading colon puts getopts in silent mode so that unknown options and
# missing arguments are reported here rather than by getopts itself.
while getopts ":h:u:d:o:m:p:a:t:" flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        o) outputfile=${OPTARG};;
        m) mode=${OPTARG};;
        p) port=${OPTARG};;
        a) use_ad_auth=${OPTARG};;
        t) trust_server_cert=${OPTARG};;
        :) echo "Option -${OPTARG} requires an argument." >&2
           echo >&2
           usage >&2
           exit 1;;
        \?) if [ "${OPTARG}" = "?" ]; then
                usage
                exit 0
            fi
            echo "Unknown option -${OPTARG}." >&2
            echo >&2
            usage >&2
            exit 1;;
    esac
done

# Validate everything before prompting for a password, so that a typo is
# reported immediately instead of after the connection has been attempted.
if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ] || [ -z "$outputfile" ]; then
    echo "Missing required option. -h, -u, -d and -o are all needed." >&2
    echo >&2
    usage >&2
    exit 1
fi

if [ "$mode" != "stats" ] && [ "$mode" != "full_metadata" ]; then
    echo "Invalid mode '${mode}'. Use 'stats' or 'full_metadata'." >&2
    exit 1
fi

if ! command -v sqlcmd >/dev/null 2>&1; then
    echo "sqlcmd was not found on PATH." >&2
    echo "Install it from https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools" >&2
    exit 1
fi

# Append the port to the server address if one was supplied.
server="$dbhost"
if [ -n "$port" ]; then
    server="$dbhost,$port"
fi

auth_flag=()
auth_label="SQL Server"
if [ "$use_ad_auth" = "1" ]; then
    auth_flag=("-G")  # Use AD authentication
    auth_label="Entra ID / Azure AD"
fi

trust_cert_flag=()
if [ "$trust_server_cert" = "1" ]; then
    trust_cert_flag=("-C")  # Trust server certificate
fi

printf '\n'
printf '  Server     %s\n' "$server"
printf '  Database   %s\n' "$database"
printf '  User       %s\n' "$username"
printf '  Auth       %s\n' "$auth_label"
printf '  Mode       %s\n' "$mode"
printf '  Output     %s\n' "$outputfile"
printf '\n'

# Read the password without letting the shell mangle it.
#   -r : do not treat backslashes as escape characters (a password such as
#        'Pa55\word' would otherwise lose its backslash)
#   -s : do not echo the password to the terminal
# The password is handed to sqlcmd through the SQLCMDPASSWORD environment
# variable rather than the -P flag, so it never passes through argv and no
# shell quoting/escaping is applied to it.
if [ -z "${SQLCMDPASSWORD:-}" ]; then
    read -r -s -p "Password: " SQLCMDPASSWORD || true
    echo
fi
export SQLCMDPASSWORD

# Connect once before running the real queries, so that a failure is reported
# on screen instead of being written to the output file and left unnoticed.
printf 'Testing connection ... '
if connection_error=$(sqlcmd -S "$server" -U "$username" -d "$database" \
    -Q "SET NOCOUNT ON; SELECT 1" "${auth_flag[@]}" "${trust_cert_flag[@]}" 2>&1); then
    printf 'ok\n'
else
    printf 'FAILED\n\n'
    printf '%s\n' "$connection_error" | sed 's/^/  /'
    cat <<'HINT'

Common causes:
  - Wrong username or password
  - -a 1 (Entra ID) used against an on-premises SQL Server
  - Host or port not reachable

HINT
    # The output file is only written once the queries run, so anything already
    # at that path is left over from an earlier run and must not be sent on.
    if [ -e "$outputfile" ]; then
        printf 'No results were collected. %s is from an earlier run.\n\n' "$outputfile"
    fi
    exit 1
fi

printf 'Collecting metadata ... '
if [ "$mode" = "stats" ]; then
  run_ok=0
  sqlcmd -S "$server" -U "$username" -i ./database_list_with_size.sql -i ./data_type_distribution.sql -i ./other_stats.sql \
  -d "$database" -o "$outputfile" "${auth_flag[@]}" "${trust_cert_flag[@]}" || run_ok=1
else
  run_ok=0
  sqlcmd -S "$server" -U "$username" -i ./queries.sql -d "$database" -o "$outputfile" "${auth_flag[@]}" "${trust_cert_flag[@]}" || run_ok=1
fi

# sqlcmd writes per-query errors, such as missing permissions, into the output
# file and still exits successfully, so the file is checked as well.
if [ "$run_ok" -ne 0 ] || grep -qE '^(Sqlcmd: Error|Msg [0-9]+,)' "$outputfile" 2>/dev/null; then
    printf 'completed with errors\n\n'
    grep -E '^(Sqlcmd: Error|Msg [0-9]+,)' "$outputfile" 2>/dev/null | head -3 | sed 's/^/  /' || true
    printf '\nReview %s before sending it.\n' "$outputfile"
    exit 1
fi
printf 'ok\n\n'

bytes=$(wc -c < "$outputfile" | tr -d ' ')
size=$(awk -v b="$bytes" 'BEGIN {
    if (b < 1024) printf "%d bytes", b
    else if (b < 1048576) printf "%.1f KB", b / 1024
    else printf "%.1f MB", b / 1048576
}')
printf 'Wrote %s (%s)\n' "$outputfile" "$size"