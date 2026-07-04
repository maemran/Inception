#!/bin/bash
set -euo pipefail

DB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(sed -n '1p' /run/secrets/credentials)"
WP_USER_PASSWORD="$(sed -n '2p' /run/secrets/credentials)"

until nc -z mariadb 3306 2>/dev/null; do
    sleep 2
done

if [ ! -f /var/www/html/wp-config.php ]; then
    wp core download --force --allow-root

    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="mariadb:3306" \
        --allow-root

    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=editor \
        --user_pass="${WP_USER_PASSWORD}" \
        --allow-root

    chown -R www-data:www-data /var/www/html
fi

exec php-fpm -F
