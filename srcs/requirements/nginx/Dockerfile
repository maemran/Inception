FROM debian:bullseye

RUN apt update -y \
    && apt install nginx openssl -y \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl

COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
RUN rm -f /etc/nginx/sites-enabled/default

RUN openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -days 365 \
    -subj "/C=JO/ST=Amman/L=Amman/O=42/OU=Inception/CN=moham.42.fr"

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
