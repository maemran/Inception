#!/bin/bash
set -euo pipefail

DB_PASSWORD="$(cat /run/secrets/db_password)"
DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

# Only initialise on the very first run: an already-initialised data
# directory (persisted in the named volume) is detected by the presence
# of the "mysql" system database.
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[init_db] First run detected, initialising MariaDB data directory..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null

    # Start a temporary server in the background, used only to run the
    # bootstrap SQL below. It is shut down before we exec the real
    # foreground server.
    mysqld_safe --skip-networking --datadir=/var/lib/mysql &
    pid="$!"

    until mysqladmin ping --silent 2>/dev/null; do
        sleep 1
    done

    mysql -u root <<-EOSQL
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --user=root --password="${DB_ROOT_PASSWORD}" shutdown
    wait "$pid"
    echo "[init_db] Initialisation complete."
fi

echo "[init_db] Starting MariaDB in the foreground..."
exec mysqld_safe --datadir=/var/lib/mysql
