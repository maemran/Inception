FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
        php7.4-fpm \
        php7.4-mysql \
        php7.4-curl \
        php7.4-gd \
        php7.4-xml \
        php7.4-mbstring \
        php7.4-zip \
        curl \
        ca-certificates \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# wp-cli is fetched once at build time, not pulled as a ready-made image
RUN curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Make php-fpm listen on TCP 9000 instead of a unix socket so nginx
# (a separate container) can reach it over the docker network.
RUN sed -i 's/^listen = .*/listen = 9000/' /etc/php/7.4/fpm/pool.d/www.conf \
    && sed -i 's/^;\?listen.owner.*/listen.owner = www-data/' /etc/php/7.4/fpm/pool.d/www.conf \
    && sed -i 's/^;\?listen.group.*/listen.group = www-data/' /etc/php/7.4/fpm/pool.d/www.conf \
    && sed -i 's/^;\?listen.allowed_clients.*/;listen.allowed_clients =/' /etc/php/7.4/fpm/pool.d/www.conf

COPY tools/wp_setup.sh /usr/local/bin/wp_setup.sh
RUN chmod +x /usr/local/bin/wp_setup.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wp_setup.sh"]
