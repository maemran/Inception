#!/bin/bash
set -euo pipefail

envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/sites-available/wordpress.conf.template \
    > /etc/nginx/sites-available/wordpress.conf

ln -sf /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/wordpress.conf

if [ ! -f /etc/nginx/ssl/inception.crt ]; then
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=JO/ST=Amman/L=Amman/O=42School/OU=Inception/CN=${DOMAIN_NAME}"
fi

exec nginx -g "daemon off;"
