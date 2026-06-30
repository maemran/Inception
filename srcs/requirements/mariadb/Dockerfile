# Penultimate stable Debian release (adjust if a newer "penultimate" is out
# by the time you build this — check https://www.debian.org/releases/)
FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/init_db.sh /usr/local/bin/init_db.sh

RUN chmod +x /usr/local/bin/init_db.sh \
    && mkdir -p /var/run/mysqld \
    && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init_db.sh"]
