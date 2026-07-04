FROM debian:bullseye-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        php-fpm \
        php-mysql \
        php-xml \
        php-zip \
        wget \
        ca-certificates \
        netcat-openbsd \
    && wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && rm -rf /var/lib/apt/lists/*

RUN chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

RUN sed -i 's/^listen = .*/listen = 9000/' /etc/php/*/fpm/pool.d/www.conf \
    && mkdir -p /run/php \
    && ln -s /usr/sbin/php-fpm* /usr/local/bin/php-fpm

WORKDIR /var/www/html

COPY tools/wordpress.sh /usr/local/bin/wordpress.sh
RUN chmod +x /usr/local/bin/wordpress.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wordpress.sh"]
