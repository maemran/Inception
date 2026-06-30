FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        openssl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl

COPY conf/wordpress.conf.template /etc/nginx/sites-available/wordpress.conf.template
COPY tools/setup.sh /usr/local/bin/setup.sh

RUN rm -f /etc/nginx/sites-enabled/default \
    && chmod +x /usr/local/bin/setup.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/setup.sh"]
