#!/bin/bash
set -euo pipefail

DB_PASSWORD="$(cat /run/secrets/db_password)"
DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

init_db() {
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
}

init_sql() {
    mysqld_safe --skip-networking --datadir=/var/lib/mysql &
    pid="$!"
    until mysqladmin ping --silent 2>/dev/null; do
        sleep 1
    done

    mysql -u root <<-EOSQL
        DELETE FROM mysql.user WHERE User='';
        DROP DATABASE IF EXISTS test;
        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --user=root --password="${DB_ROOT_PASSWORD}" shutdown
    wait "$pid"
}

if [ ! -d "/var/lib/mysql/mysql" ]; then
    init_db
    init_sql
elif [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    init_sql
fi

exec mysqld_safe --datadir=/var/lib/mysql
