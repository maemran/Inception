#!/bin/bash
set -e

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

DB_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

sed -i "s/127.0.0.1/0.0.0.0/" "/etc/mysql/mariadb.conf.d/50-server.cnf"

if [ ! -d /var/lib/mysql/init ]; then
    cat > /tmp/init.sql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
    mkdir -p /var/lib/mysql/init
    exec mariadbd --user=mysql --datadir=/var/lib/mysql --init-file=/tmp/init.sql
fi

exec mariadbd --user=mysql --datadir=/var/lib/mysql
