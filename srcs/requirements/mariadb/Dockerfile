FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends\
 mariadb-server && rm -rf /var/lib/apt/lists/*

COPY ./tools/init_db.sh .
RUN chmod +x init_db.sh

EXPOSE 3306

ENTRYPOINT ["./init_db.sh"]
