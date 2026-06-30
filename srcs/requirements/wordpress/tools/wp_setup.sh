#!/bin/bash
set -euo pipefail

DB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(sed -n '1p' /run/secrets/credentials)"
WP_USER_PASSWORD="$(sed -n '2p' /run/secrets/credentials)"

echo "[wp_setup] Waiting for MariaDB to be reachable..."
until mysqladmin ping -h"mariadb" -u"${MYSQL_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; do
    sleep 2
done

if [ ! -f /var/www/html/wp-config.php ]; then
    echo "[wp_setup] First run detected, installing WordPress..."

    wp core download --allow-root

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

    # Second, non-administrator user (subject requires at least two users)
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=editor \
        --user_pass="${WP_USER_PASSWORD}" \
        --allow-root

    chown -R www-data:www-data /var/www/html
    echo "[wp_setup] WordPress installation complete."
else
    echo "[wp_setup] Existing installation found in the persisted volume, skipping install."
fi

echo "[wp_setup] Starting php-fpm in the foreground..."
exec php-fpm7.4 -F
