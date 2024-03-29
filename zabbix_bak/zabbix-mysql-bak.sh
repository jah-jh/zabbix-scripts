#!/usr/bin/env bash
#
# NAME
#     zabbix-dump - Configuration Backup for Zabbix' MySQL or PostgreSQL data
#
# VERSION
#     0.9.1
#
# SYNOPSIS
#     This is a MySQL configuration backup script for Zabbix 1.x, 2.x, 3.x and 4.x.
#     It does a full backup of all configuration tables, but only a schema
#     backup of large data tables.
#
#     The script is based on a script by Ricardo Santos
#     (http://zabbixzone.com/zabbix/backuping-only-the-zabbix-configuration/)
#
# CONTRIBUTORS
#      - Ricardo Santos
#      - Jens Berthold (maxhq)
#      - Oleksiy Zagorskyi (zalex)
#      - Petr Jendrejovsky
#      - Jonathan Bayer
#      - Andreas Niedermann (dre-)
#      - Mișu Moldovan (dumol)
#      - Daniel Schneller (dschneller)
#      - Ruslan Ohitin (ruslan-ohitin)
#      - Jonathan Wright (neonardo1)
#      - msjmeyer
#      - Sergey Galkin (sergeygalkin)
#      - Greg Cockburn (gergnz)
#      - yangqi
#      - Johannes Petz (PetzJohannes)
#      - Wesley Schaft (wschaft)
#      - Tiago Cruz (tiago-cruz-movile)
#
# AUTHOR
#     Jens Berthold (maxhq), 2019
#
# LICENSE
#     This script is released under the MIT License (see LICENSE.txt)


#
# DEFAULT VALUES
#
# DO NOT EDIT THESE VALUES!
# Instead, use command line parameters or a config file to specify options.
#
#DUMPDIR="$PWD"
DUMPDIR="/tmp"
DBTYPE="mysql"
DEFAULT_DBHOST="127.0.0.1"
DEFAULT_DBNAME="zabbix"
DEFAULT_DBUSER="zabbix"
DEFAULT_DBPASS=""
COMPRESSION="gz"
QUIET="no"
REVERSELOOKUP="yes"
GENERATIONSTOKEEP=0
ZBX_CONFIG="/etc/zabbix/zabbix_server.conf"
READ_ZBX_CONFIG="yes"

#
# SHOW HELP
#
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
USAGE
    $(basename "${BASH_SOURCE[*]}") [options]

OPTIONS
    -t DATABASE_TYPE
        Database type (mysql or psql).
        Default: $DBTYPE

    -H DBHOST
        Hostname/IP of database server (DBMS).
        Default: $DEFAULT_DBHOST

    -P DBPORT
        DBMS port.
        Default for mysql: 3306
        Default for psql:  5432

    -s DBSOCKET
        Path to DBMS socket file.
        Can be used as an alternative to specifying host (and maybe port).

    -d DATABASE
        Name of Zabbix database.
        Default: $DEFAULT_DBNAME

    -u DBUSER
        DBMS user to access Zabbix database.
        Default: $DEFAULT_DBUSER

    -p DBPASSWORD
        DBMS user password (specify "-" for a prompt).
        Default: no password

    -o DIR
        Save Zabbix database dumps to DIR.
        Default: $DUMPDIR

    -z ZABBIX_CONFIG
        Read database host and credentials from given Zabbix config file.
        Default: $ZBX_CONFIG

    -Z
        Do not try to read the Zabbix server configuration.

    -c MYSQL_CONFIG
        MySQL only:
        Read database host and credentials from given MySQL config file.
        PLEASE NOTE:
        The first "database" option found in the config file is used for
        mysqldump (it needs the database to be specified via command line).

    -r NUM
        Rotate backups while keeping up to NUM generations.
        Uses filename to match.
        Default: keep all backups

    -x
        Compress using XZ instead of GZip.
        PLEASE NOTE:
        XZ compression will take much longer and consume more CPU time
        but the resulting backup will be about half the size of the same
        sql dump compressed using GZip. Your mileage may vary.

    -0
        Do not compress the sql dump

    -n
        Skip reverse lookup of IP address for host.

    -q
        Quiet mode: no output except for errors (for batch/crontab use).

    -h
    --help
        Show this help.

EXAMPLES
    # read $ZBX_CONFIG to backup local Zabbix server's
    # MySQL database into current directory
    $(basename "${BASH_SOURCE[*]}")

    # ...same for PostgreSQL
    $(basename "${BASH_SOURCE[*]}") -t psql

    # DO NOT read $ZBX_CONFIG,
    # use instead to backup local MySQL database and ask for password
    $(basename "${BASH_SOURCE[*]}") -Z -p -

    # read DB options from given Zabbix config file
    $(basename "${BASH_SOURCE[*]}") -z /opt/etc/zabbix_server.conf

    # specify MySQL database and user, ask for password
    $(basename "${BASH_SOURCE[*]}") -Z -d zabbixdb -u zabbix -p - -o /tmp

    # read DB options from MySQL config file
    $(basename "${BASH_SOURCE[*]}") -c /etc/mysql/mysql.cnf
    # ...and overwrite database name
    $(basename "${BASH_SOURCE[*]}") -c /etc/mysql/mysql.cnf -d zabbixdb

EOF
    exit 1
fi

#
# PARSE COMMAND LINE ARGUMENTS
#
DB_GIVEN=0
while getopts ":c:d:H:o:p:P:r:s:t:u:z:0nqxZ" opt; do
    case $opt in
        t)  DBTYPE="$OPTARG" ;;
        H)  ODBHOST="$OPTARG" ;;
        s)  ODBSOCKET="$OPTARG" ;;
        d)  ODBNAME="$OPTARG"; DB_GIVEN=1 ;;
        u)  ODBUSER="$OPTARG" ;;
        P)  ODBPORT="$OPTARG" ;;
        p)  ODBPASS="$OPTARG" ;;
        c)  MYSQL_CONFIG="$OPTARG" ;;
        o)  DUMPDIR="$OPTARG" ;;
        z)  ZBX_CONFIG="$OPTARG" ;;
        Z)  READ_ZBX_CONFIG="no" ;;
        r)  GENERATIONSTOKEEP=$(printf '%.0f' "$OPTARG") ;;
        x)  COMPRESSION="xz" ;;
        0)  COMPRESSION="" ;;
        n)  REVERSELOOKUP="no" ;;
        q)  QUIET="yes" ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        :)  echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
    esac
done

[ ! -z "$MYSQL_CONFIG" ] && READ_ZBX_CONFIG="no"

# (Try) reading database config from zabbix_server.conf
if [[ "${READ_ZBX_CONFIG}" == "yes" && -f "${ZBX_CONFIG}" && -r "${ZBX_CONFIG}" ]]; then
    [ "$QUIET" == "no" ] && echo "Reading database options from ${ZBX_CONFIG}..."
    source "${ZBX_CONFIG}"

    # set non-existing variables to their Zabbix defaults (if they are non-empty string)
    [ -z ${DBHost+x} ] && DBHost="localhost"

    # Zabbix config has a special treatment for DBHost:
    # > If set to localhost, socket is used for MySQL.
    # > If set to empty string, socket is used for PostgreSQL.
    if [[ ( "$DBTYPE" == "mysql" && "${DBHost}" == "localhost" ) || ( "$DBTYPE" == "psql" && "${DBHost}" == "" ) ]]; then
        [ "$DBTYPE" == "mysql" ] && searchstr="mysql"
        [ "$DBTYPE" == "psql" ] && searchstr="postgres"
        sock=$(netstat -axn | grep -m1 "$searchstr" | sed -r 's/^.*\s+([^ ]+)$/\1/')
        if [[ ! -z "$sock" && -S $sock ]]; then DBSOCKET="$sock"; DBHOST=""; else DBHOST="${DBHost}"; fi
    else
        DBHOST="${DBHost}"
        DBSOCKET="${DBSocket}"
    fi

    DBPORT="${DBPort}"
    DBNAME="${DBName}"
    DBUSER="${DBUser}"
    DBPASS="${DBPassword}"
# Otherwise: set default values
else
    # if a MySQL config file is specified we assume it contains all connection parameters
    if [ -z "$MYSQL_CONFIG" ]; then
        DBHOST="$DEFAULT_DBHOST"
        DBNAME="$DEFAULT_DBNAME"
        DBUSER="$DEFAULT_DBUSER"
        DBPASS="$DEFAULT_DBPASS"
    fi
fi

# Always set default ports, even if we read other parameters from zabbix_server.conf
[[ -z "$DBPORT" && "$DBTYPE" == "mysql" ]] && DBPORT="3306"
[[ -z "$DBPORT" && "$DBTYPE" == "psql"  ]] && DBPORT="5432"

# Options specified via command line override defaults or those from zabbix_server.conf (if any)
[ ! -z "$ODBHOST" ] && DBHOST=$ODBHOST
[ ! -z "$ODBPORT" ] && DBPORT=$ODBPORT
[ ! -z "$ODBSOCKET" ] && DBSOCKET=$ODBSOCKET && DBHOST=""
[ ! -z "$ODBNAME" ] && DBNAME=$ODBNAME
[ ! -z "$ODBUSER" ] && DBUSER=$ODBUSER
[ ! -z "$ODBPASS" ] && DBPASS=$ODBPASS

# Password prompt
if [ "$DBPASS" = "-" ]; then
    read -r -s -p "Enter database password for user '$DBUSER' (input will be hidden): " DBPASS
    echo ""
fi

# MySQL config file validations
if [ ! -z "$MYSQL_CONFIG" ]; then
    if [ ! -r "$MYSQL_CONFIG" ]; then
        echo "ERROR: Cannot read configuration file $MYSQL_CONFIG" >&2
        exit 1
    fi
    # Database name needs special treatment:
    # For mysqldump it has to be specified on the command line!
    # Therefore we need to get it from the config file
    if [ $DB_GIVEN -eq 0 ]; then
        DBNAME=$(grep -m 1 ^database= "$MYSQL_CONFIG" | cut -d= -f2)
    fi
fi

if [ -z "$DBNAME" ]; then
    echo "ERROR: Please specify a database name (option -d)"
    exit 1
fi

#
# CONSTANTS
#
SUFFIX=""; test ! -z $COMPRESSION && SUFFIX=".${COMPRESSION}"

DB_OPTS=()
case $DBTYPE in
    mysql)
        [ ! -z "$MYSQL_CONFIG" ] && DB_OPTS=("${DB_OPTS[@]}" --defaults-extra-file="$MYSQL_CONFIG")
        [ ! -z "$DBSOCKET" ] && DB_OPTS=("${DB_OPTS[@]}" -S $DBSOCKET)
        [ ! -z "$DBHOST" ] && DB_OPTS=("${DB_OPTS[@]}" -h $DBHOST)
        [ ! -z "$DBUSER" ] && DB_OPTS=("${DB_OPTS[@]}" -u $DBUSER)
        [ ! -z "$DBPASS" ] && DB_OPTS=("${DB_OPTS[@]}" -p"$DBPASS")
        DB_OPTS=("${DB_OPTS[@]}" -P"$DBPORT")
        DB_OPTS_BATCH=("${DB_OPTS[@]}" --batch --silent)
        [ ! -z "$DBNAME" ] && DB_OPTS_BATCH=("${DB_OPTS_BATCH[@]}" -D $DBNAME)
        ;;
    psql)
        [ ! -z "$DBSOCKET" ] && DB_OPTS=("${DB_OPTS[@]}" -h $DBSOCKET)
        [ ! -z "$DBHOST" ] && DB_OPTS=("${DB_OPTS[@]}" -h $DBHOST)
        [ ! -z "$DBUSER" ] && DB_OPTS=("${DB_OPTS[@]}" -U $DBUSER)
        DB_OPTS=("${DB_OPTS[@]}" -p"$DBPORT")
        if [ ! -z "$DBPASS" ]; then
           export PGPASSFILE=$(mktemp -u)
           echo "$DBHOST:$DBPORT:$DBNAME:$DBUSER:$DBPASS" > $PGPASSFILE
           chmod 600 $PGPASSFILE
        fi
        DB_OPTS_BATCH=("${DB_OPTS[@]}" -Atw)
        [ ! -z "$DBNAME" ] && DB_OPTS_BATCH=("${DB_OPTS_BATCH[@]}" -d $DBNAME)
        ;;
esac

# Log file for errors
ERRORLOG=$(mktemp)

# Host name: try reverse lookup if IP is given
DBHOSTNAME="$DBHOST"
command -v dig >/dev/null 2>&1
FIND_DIG=$?
if [ "$REVERSELOOKUP" == "yes" ] && [ $FIND_DIG -eq 0 ] && [ ! -z "$DBHOST" ]; then
    # Try resolving a given host ip
    newHostname=$(dig +noall +answer -x "${DBHOST}" | sed -r 's/((\S+)\s+)+([^\.]+)\..*/\3/')
    test \! -z "$newHostname" && DBHOSTNAME="$newHostname"
fi

#
# CONFIG DUMP
#
if [ "$QUIET" == "no" ]; then
    cat <<-EOF
Configuration:
 - type:     $DBTYPE
EOF
    [ ! -z "$MYSQL_CONFIG" ] && echo " - cfg file: $MYSQL_CONFIG"
    [ ! -z "$DBHOST" ] && echo " - host:     $DBHOST ($DBHOSTNAME)" && echo " - port:     $DBPORT"
    [ ! -z "$DBSOCKET" ] && echo " - socket:   $DBSOCKET"
    [ ! -z "$DBNAME" ] && echo " - database: $DBNAME"
    [ ! -z "$DBUSER" ] && echo " - user:     $DBUSER"
    [ ! -z "$DUMPDIR" ] && echo " - output:   $DUMPDIR"
fi

#
# FUNCTIONS
#

# Returns TRUE if argument 1 is part of the given array (remaining arguments)
elementIn () {
    local e
    for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
    return 1
}
check_binary() {
    if ! which $1 > /dev/null; then
        echo "Executable '$1' not found." >&2
        case $1 in
            mysql)
                echo "(with Debian try \"apt-get install mysql-client\")" >&2 ;;
            psql)
                echo "(with Debian try \"apt-get install postgresql-client\")" >&2 ;;
        esac
        exit 1
    fi
}
clean_psql_pass() {
    if [ $DBTYPE = "psql" -a -n "$PGPASSFILE" ]; then
       echo rm -f $PGPASSFILE
    fi
}

#
# CHECKS
#
case $DBTYPE in
    mysql)
        check_binary mysqldump ;;
    psql)
        check_binary pg_dump ;;
    *)
        echo "Sorry, database type '$DBTYPE' is not supported."
        echo "Please specify either 'mysql' or 'psql'."
        exit 1 ;;
esac

#
# READ TABLE LIST from __DATA__ section at the end of this script
# (http://stackoverflow.com/a/3477269/2983301)
#
DATA_TABLES=()
while read -r line; do
    table=$(echo "$line" | cut -d" " -f1)
    echo "$line" | cut -d" " -f5 | grep -qi "SCHEMAONLY"
    test $? -eq 0 && DATA_TABLES+=($table)
done < <(sed '0,/^__DATA__$/d' "${BASH_SOURCE[*]}" | tr -s " ")

# paranoid check
if [ ${#DATA_TABLES[@]} -lt 5 ]; then
    echo "ERROR: The number of large data tables configured in this script is less than 5." >&2
    exit 1
fi

#
# BACKUP
#
# Read table list from database
[ "$QUIET" == "no" ] && echo "Fetching list of existing tables..."
case $DBTYPE in
    mysql)
        DB_TABLES=$(mysql "${DB_OPTS_BATCH[@]}" -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$DBNAME'" 2>$ERRORLOG)
        ;;
    psql)
        DB_TABLES=$(psql "${DB_OPTS_BATCH[@]}" -c "SELECT table_name FROM information_schema.tables  WHERE table_schema='public' AND table_type='BASE TABLE'" 2>$ERRORLOG)
        ;;
esac
if [ $? -ne 0 ]; then
    echo "ERROR while trying to access database:" 2>&1;
    cat $ERRORLOG 2>&1;
    clean_psql_pass
    exit 1;
fi

DB_TABLES=$(echo "$DB_TABLES" | sort)
DB_TABLE_NUM=$(echo "$DB_TABLES" | wc -l)

# Query Zabbix database version
VERSION=""
case $DBTYPE in
    mysql)
        DB_VER=$(mysql "${DB_OPTS_BATCH[@]}" -N -e "select optional from dbversion;" 2>/dev/null)
        ;;
    psql)
        DB_VER=$(psql "${DB_OPTS_BATCH[@]}" -c "select optional from dbversion;" 2>/dev/null)
        ;;
esac
if [ $? -eq 0 ]; then
    # version string is like: 02030015
    re='(.*)([0-9]{2})([0-9]{4})'
    if [[ $DB_VER =~ $re ]]; then
        VERSION="_db-${DBTYPE}-${BASH_REMATCH[1]}.$(( ${BASH_REMATCH[2]} + 0 )).$(( ${BASH_REMATCH[3]} + 0 ))"
    fi
fi

# Assemble file name
DUMPFILENAME_PREFIX="zabbix_cfg_${DBHOSTNAME}"
DUMPFILEBASE="${DUMPFILENAME_PREFIX}_$(date +%Y%m%d-%H%M)${VERSION}.sql"
DUMPFILE="$DUMPDIR/$DUMPFILEBASE"

PROCESSED_DATA_TABLES=()
i=0

mkdir -p "${DUMPDIR}"

[ "$QUIET" == "no" ] && echo "Starting table backups..."
case $DBTYPE in
    mysql)
        while read table; do
            # large data tables: only store schema
            if elementIn "$table" "${DATA_TABLES[@]}"; then
                dump_opt="--no-data"
                PROCESSED_DATA_TABLES+=($table)
            # configuration tables: full dump
            else
                dump_opt="--extended-insert=FALSE"
            fi

            mysqldump "${DB_OPTS[@]}" \
                --routines --opt --single-transaction --skip-lock-tables \
                $dump_opt \
                $DBNAME --tables ${table} >> "$DUMPFILE" 2>$ERRORLOG

            if [ $? -ne 0 ]; then echo -e "\nERROR: Could not backup table ${table}:" >&2; cat $ERRORLOG >&2; exit 1; fi

            if [ "$QUIET" == "no" ]; then
                # show percentage
                i=$((i+1)); i_percent=$(($i * 100 / $DB_TABLE_NUM))
                if [ $(($i_percent % 12)) -eq 0 ]; then
                    echo -n "${i_percent}%"
                else
                    if [ $(($i_percent % 2)) -eq 0 ]; then echo -n "."; fi
                fi
            fi
        done <<<"$DB_TABLES"
    ;;
    psql)
        while read table; do
            if elementIn "$table" "${DATA_TABLES[@]}"; then
                dump_opt="--exclude-table-data=$table"
                PROCESSED_DATA_TABLES+=($dump_opt)
            fi
        done <<<"$DB_TABLES"

        pg_dump "${DB_OPTS[@]}" ${PROCESSED_DATA_TABLES[@]} > "$DUMPFILE" 2>$ERRORLOG
        if [ $? -ne 0 ]; then
            echo -e "\nERROR: Could not backup database." >&2
            cat $ERRORLOG >&2
            clean_psql_pass
            exit 1
        fi
    ;;
esac

rm $ERRORLOG

#
# COMPRESS BACKUP
#
if [ "$QUIET" == "no" ]; then
    echo -e "\n"
    echo "For the following large tables only the schema (without data) was stored:"
    for table in "${PROCESSED_DATA_TABLES[@]}"; do echo " - $table"; done

    echo
    echo "Compressing backup file..."
fi

EXITCODE=0
if [ "$COMPRESSION" == "gz" ]; then gzip -f "$DUMPFILE"; EXITCODE=$?; fi
if [ "$COMPRESSION" == "xz" ]; then xz   -f "$DUMPFILE"; EXITCODE=$?; fi
if [ $EXITCODE -ne 0 ]; then
    echo -e "\nERROR: Could not compress backup file, see previous messages" >&2
    clean_psql_pass
    exit 1
fi

[ "$QUIET" == "no" ] && echo -e "\nBackup Completed:\n${DUMPFILE}${SUFFIX}"

#
# ROTATE OLD BACKUPS
#
if [ $GENERATIONSTOKEEP -gt 0 ]; then
    [ "$QUIET" == "no" ] && echo "Removing old backups, keeping up to $GENERATIONSTOKEEP"
    REMOVE_OLD_CMD="cd \"$DUMPDIR\" && ls -t \"${DUMPFILENAME_PREFIX}\"* | /usr/bin/awk \"NR>${GENERATIONSTOKEEP}\" | xargs rm -f "
    eval ${REMOVE_OLD_CMD}
    if [ $? -ne 0 ]; then
        echo "ERROR: Could not rotate old backups" >&2
        clean_psql_pass
        exit 1
    fi
fi

clean_psql_pass
exit 0

################################################################################
# List of all known table names.
# The flag SCHEMAONLY marks tables that contain monitoring data (as opposed to
# config data), so only their database schema will be backed up.
#

__DATA__
acknowledges               1.3.1    - 4.0.0  SCHEMAONLY
actions                    1.3.1    - 4.0.0
alerts                     1.3.1    - 4.0.0  SCHEMAONLY
application_discovery      2.5.0    - 4.0.0
application_prototype      2.5.0    - 4.0.0
application_template       2.1.0    - 4.0.0
applications               1.3.1    - 4.0.0
auditlog                   1.3.1    - 4.0.0  SCHEMAONLY
auditlog_details           1.7      - 4.0.0  SCHEMAONLY
autoreg                    1.3.1    - 1.3.4
autoreg_host               1.7      - 4.0.0
conditions                 1.3.1    - 4.0.0
config                     1.3.1    - 4.0.0
corr_condition             3.2.0    - 4.0.0
corr_condition_group       3.2.0    - 4.0.0
corr_condition_tag         3.2.0    - 4.0.0
corr_condition_tagpair     3.2.0    - 4.0.0
corr_condition_tagvalue    3.2.0    - 4.0.0
corr_operation             3.2.0    - 4.0.0
correlation                3.2.0    - 4.0.0
dashboard                  3.4.0    - 4.0.0
dashboard_user             3.4.0    - 4.0.0
dashboard_usrgrp           3.4.0    - 4.0.0
dbversion                  2.1.0    - 4.0.0
dchecks                    1.3.4    - 4.0.0
dhosts                     1.3.4    - 4.0.0
drules                     1.3.4    - 4.0.0
dservices                  1.3.4    - 4.0.0
escalations                1.5.3    - 4.0.0
event_recovery             3.2.0    - 4.0.0  SCHEMAONLY
event_suppress             4.0.0    - 4.0.0  SCHEMAONLY
event_tag                  3.2.0    - 4.0.0  SCHEMAONLY
events                     1.3.1    - 4.0.0  SCHEMAONLY
expressions                1.7      - 4.0.0
functions                  1.3.1    - 4.0.0
globalmacro                1.7      - 4.0.0
globalvars                 1.9.6    - 4.0.0
graph_discovery            1.9.0    - 4.0.0
graph_theme                1.7      - 4.0.0
graphs                     1.3.1    - 4.0.0
graphs_items               1.3.1    - 4.0.0
group_discovery            2.1.4    - 4.0.0
group_prototype            2.1.4    - 4.0.0
groups                     1.3.1    - 3.4.1
help_items                 1.3.1    - 2.1.8
history                    1.3.1    - 4.0.0  SCHEMAONLY
history_log                1.3.1    - 4.0.0  SCHEMAONLY
history_str                1.3.1    - 3.4.1  SCHEMAONLY
history_str_sync           1.3.1    - 2.2.13 SCHEMAONLY
history_sync               1.3.1    - 2.2.13 SCHEMAONLY
history_text               1.3.1    - 4.0.0  SCHEMAONLY
history_uint               1.3.1    - 4.0.0  SCHEMAONLY
history_uint_sync          1.3.1    - 2.2.13 SCHEMAONLY
host_discovery             2.1.4    - 4.0.0
host_inventory             1.9.6    - 4.0.0
host_profile               1.9.3    - 1.9.5
hostmacro                  1.7      - 4.0.0
hosts                      1.3.1    - 4.0.0
hosts_groups               1.3.1    - 4.0.0
hosts_profiles             1.3.1    - 1.9.2
hosts_profiles_ext         1.6      - 1.9.2
hosts_templates            1.3.1    - 4.0.0
housekeeper                1.3.1    - 4.0.0
hstgrp                     4.0.0    - 4.0.0
httpstep                   1.3.3    - 4.0.0
httpstep_field             3.4.0    - 4.0.0
httpstepitem               1.3.3    - 4.0.0
httptest                   1.3.3    - 4.0.0
httptest_field             3.4.0    - 4.0.0
httptestitem               1.3.3    - 4.0.0
icon_map                   1.9.6    - 4.0.0
icon_mapping               1.9.6    - 4.0.0
ids                        1.3.3    - 4.0.0
images                     1.3.1    - 4.0.0
interface                  1.9.1    - 4.0.0
interface_discovery        2.1.4    - 4.0.0
item_application_prototype 2.5.0    - 4.0.0
item_condition             2.3.0    - 4.0.0
item_discovery             1.9.0    - 4.0.0
item_preproc               3.4.0    - 4.0.0
items                      1.3.1    - 4.0.0
items_applications         1.3.1    - 4.0.0
maintenance_tag            4.0.0    - 4.0.0
maintenances               1.7      - 4.0.0
maintenances_groups        1.7      - 4.0.0
maintenances_hosts         1.7      - 4.0.0
maintenances_windows       1.7      - 4.0.0
mappings                   1.3.1    - 4.0.0
media                      1.3.1    - 4.0.0
media_type                 1.3.1    - 4.0.0
node_cksum                 1.3.1    - 2.2.13
node_configlog             1.3.1    - 1.4.7
nodes                      1.3.1    - 2.2.13
opcommand                  1.9.4    - 4.0.0
opcommand_grp              1.9.2    - 4.0.0
opcommand_hst              1.9.2    - 4.0.0
opconditions               1.5.3    - 4.0.0
operations                 1.3.4    - 4.0.0
opgroup                    1.9.2    - 4.0.0
opinventory                3.0.0    - 4.0.0
opmediatypes               1.7      - 1.8.22
opmessage                  1.9.2    - 4.0.0
opmessage_grp              1.9.2    - 4.0.0
opmessage_usr              1.9.2    - 4.0.0
optemplate                 1.9.2    - 4.0.0
problem                    3.2.0    - 4.0.0  SCHEMAONLY
problem_tag                3.2.0    - 4.0.0  SCHEMAONLY
profiles                   1.3.1    - 4.0.0
proxy_autoreg_host         1.7      - 4.0.0
proxy_dhistory             1.5      - 4.0.0
proxy_history              1.5.1    - 4.0.0
regexps                    1.7      - 4.0.0
rights                     1.3.1    - 4.0.0
screen_user                3.0.0    - 4.0.0
screen_usrgrp              3.0.0    - 4.0.0
screens                    1.3.1    - 4.0.0
screens_items              1.3.1    - 4.0.0
scripts                    1.5      - 4.0.0
service_alarms             1.3.1    - 4.0.0
services                   1.3.1    - 4.0.0
services_links             1.3.1    - 4.0.0
services_times             1.3.1    - 4.0.0
sessions                   1.3.1    - 4.0.0
slides                     1.3.4    - 4.0.0
slideshow_user             3.0.0    - 4.0.0
slideshow_usrgrp           3.0.0    - 4.0.0
slideshows                 1.3.4    - 4.0.0
sysmap_element_trigger     3.4.0    - 4.0.0
sysmap_element_url         1.9.0    - 4.0.0
sysmap_shape               3.4.0    - 4.0.0
sysmap_url                 1.9.0    - 4.0.0
sysmap_user                3.0.0    - 4.0.0
sysmap_usrgrp              3.0.0    - 4.0.0
sysmaps                    1.3.1    - 4.0.0
sysmaps_elements           1.3.1    - 4.0.0
sysmaps_link_triggers      1.5      - 4.0.0
sysmaps_links              1.3.1    - 4.0.0
tag_filter                 4.0.0    - 4.0.0
task                       3.2.0    - 4.0.0  SCHEMAONLY
task_acknowledge           3.4.0    - 4.0.0  SCHEMAONLY
task_check_now             4.0.0    - 4.0.0  SCHEMAONLY
task_close_problem         3.2.0    - 4.0.0  SCHEMAONLY
task_remote_command        3.4.0    - 4.0.0  SCHEMAONLY
task_remote_command_result 3.4.0    - 4.0.0  SCHEMAONLY
timeperiods                1.7      - 4.0.0
trends                     1.3.1    - 4.0.0  SCHEMAONLY
trends_uint                1.5      - 4.0.0  SCHEMAONLY
trigger_depends            1.3.1    - 4.0.0
trigger_discovery          1.9.0    - 4.0.0
trigger_tag                3.2.0    - 4.0.0
triggers                   1.3.1    - 4.0.0
user_history               1.7      - 2.4.8
users                      1.3.1    - 4.0.0
users_groups               1.3.1    - 4.0.0
usrgrp                     1.3.1    - 4.0.0
valuemaps                  1.3.1    - 4.0.0
widget                     3.4.0    - 4.0.0
widget_field               3.4.0    - 4.0.0
