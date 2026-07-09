FROM debian:bullseye

RUN apt-get update  \
    && apt-get install -y --no-install-recommends\
    netcat-openbsd \
    php-fpm \
    php-mysql\
    php-xml \
    php-zip wget ca-certificates \
    && wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && rm -rf /var/lib/apt/lists/*
COPY tools/wordpress.sh .
RUN php wp-cli.phar --info
RUN chmod +x wp-cli.phar
RUN mv wp-cli.phar /usr/local/bin/wp
RUN chmod +x wordpress.sh

ENTRYPOINT ["./wordpress.sh"]
