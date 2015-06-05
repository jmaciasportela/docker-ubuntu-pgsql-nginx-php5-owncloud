#!/bin/bash

# Start postgres without grant tables
/sbin/setuser postgres /usr/lib/postgresql/9.3/bin/postgres -D /var/lib/postgresql/9.3/main -c config_file=/etc/postgresql/9.3/main/postgresql.conf &

sleep 5

DB_ROOT_USER=${DB_REMOTE_ROOT_USER:-"root"}
DB_ROOT_PASS=${DB_REMOTE_ROOT_PASS:-"owncloud"}

if [ $DB_ROOT_USER == 'owncloud' ]; then
    /sbin/setuser postgres psql --command "ALTER USER owncloud PASSWORD '$DB_ROOT_PASS';"
else
    /sbin/setuser postgres psql --command "CREATE USER $DB_ROOT_USER WITH SUPERUSER CREATEDB PASSWORD '$DB_ROOT_PASS';"
fi

# Sleep for 5 while the postgres process
sleep 2

# Kill the insecure postgres process
killall -v postgres