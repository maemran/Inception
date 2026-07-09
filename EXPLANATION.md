# Inception — Complete Project Explanation

> **Author:** moham  
> **Subject:** 42 Inception — System Administration / Docker Infrastructure

---

## Table of Contents

1. [What is the Inception project?](#1-what-is-the-inception-project)
2. [Project structure overview](#2-project-structure-overview)
3. [Docker concepts](#3-docker-concepts)
4. [The three services (containers)](#4-the-three-services-containers)
5. [How containers communicate](#5-how-containers-communicate)
6. [Volumes and data persistence](#6-volumes-and-data-persistence)
7. [Secrets and environment variables](#7-secrets-and-environment-variables)
8. [The .env file explained](#8-the-env-file-explained)
9. [TLS / SSL — what it is and why we use it](#9-tls-ssl--what-it-is-and-why-we-use-it)
10. [NGINX in detail](#10-nginx-in-detail)
11. [MariaDB in detail](#11-mariadb-in-detail)
12. [WordPress + PHP-FPM in detail](#12-wordpress--php-fpm-in-detail)
13. [The Makefile explained](#13-the-makefile-explained)
14. [docker-compose.yml explained line by line](#14-docker-composeyml-explained-line-by-line)
15. [Lifecycle of a request](#15-lifecycle-of-a-request)
16. [Security considerations](#16-security-considerations)

---

## 1. What is the Inception project?

Inception is a **system administration** project from 42 School. The goal is to
set up a small **web infrastructure** using **Docker** containers. You must
build everything from scratch — no pre-made Docker images (like the official
`wordpress:latest` or `nginx:latest` from Docker Hub). You start from a bare
**Debian** base image and install and configure each service manually.

### What you end up with

Three containers running on one machine:

| Container   | Role |
|-------------|------|
| **NGINX**   | The **only** entry point. Listens on port 443 (HTTPS). Acts as a reverse proxy and serves static files. |
| **WordPress** | Runs PHP-FPM to process PHP requests. Contains the WordPress CMS code (downloaded by WP-CLI on first run). |
| **MariaDB** | Relational database that stores all WordPress data (posts, users, comments, etc.). |

The three containers are connected by a **custom Docker network** called
`inception`. Only NGINX is exposed to the outside world (port 443). WordPress
and MariaDB are **internal** — they cannot be reached directly from your
browser or from outside the Docker network.

---

## 2. Project structure overview

```
Inception/
├── Makefile                          # Entry point: build, start, stop, clean
├── secrets/                          # Sensitive data (gitignored)
│   ├── db_password.txt               # MariaDB application user password
│   ├── db_root_password.txt          # MariaDB root password
│   └── credentials.txt               # WordPress admin + editor passwords
├── srcs/
│   ├── .env                          # Non-secret configuration variables
│   ├── docker-compose.yml            # Orchestrates all containers
│   └── requirements/
│       ├── mariadb/
│       │   ├── Dockerfile            # How to build the MariaDB image
│       │   └── tools/
│       │       └── init_db.sh        # Entrypoint: initialises DB, starts server
│       ├── wordpress/
│       │   ├── Dockerfile            # How to build the WordPress/PHP image
│       │   └── tools/
│       │       └── wordpress.sh      # Entrypoint: waits for DB, installs WP, starts PHP-FPM
│       └── nginx/
│           ├── Dockerfile            # How to build the NGINX image
│           └── conf/
│               └── nginx.conf        # NGINX virtual host config (static, hardcoded domain)
├── DEV_DOC.md                        # Developer documentation
├── USER_DOC.md                       # End-user documentation
└── EXPLANATION.md                    # This file
```

### Why this structure?

- **`requirements/`** — each service gets its own folder with its Dockerfile,
  configuration files, and scripts. This keeps things organised and matches the
  subject's requirement.
- **`secrets/`** — separated from code so they are never committed to git.
- **`srcs/.env`** — lives next to `docker-compose.yml` because Docker Compose
  automatically picks up a file named `.env` in the same directory.

---

## 3. Docker concepts

### 3.1 What is Docker?

Docker is a tool that lets you package an application with everything it needs
to run (libraries, system tools, configuration) into a **container**. A
container is like a lightweight virtual machine — it has its own filesystem,
process space, and network — but it shares the host operating system's kernel,
so it starts in seconds and uses fewer resources.

### 3.2 Image vs Container

- **Image**: a read-only template (like a recipe). You build an image with
  `docker build` or `docker compose build`.
- **Container**: a running instance of an image. You start it with `docker run`
  or `docker compose up`.

### 3.3 Dockerfile

A text file containing instructions to build an image. Each instruction creates
a **layer**. For example:

```dockerfile
FROM debian:bullseye              # Layer 1: base OS
RUN apt-get install nginx         # Layer 2: install software
COPY conf/file.conf /etc/nginx/   # Layer 3: add config files
CMD ["nginx", "-g", "daemon off;"] # Metadata: what to run when container starts
```

Layers are cached, so rebuilding after changing a file only re-runs the
affected layers.

### 3.4 Docker Compose

A tool for defining and running **multiple containers** together using a YAML
file (`docker-compose.yml`). Instead of running three separate `docker run`
commands with many flags, you describe everything in one file.

### 3.5 Docker Network

By default, containers are isolated. A **Docker network** lets them communicate
using container names as hostnames. For example, from the `wordpress`
container, you can reach the `mariadb` container at the hostname `mariadb`
(instead of an IP address).

### 3.6 Docker Volumes

When a container is deleted, its filesystem is lost. **Volumes** are a way to
persist data outside the container's filesystem. They can be backed by a
directory on the host (bind mount) or managed by Docker.

---

## 4. The three services (containers)

### 4.1 NGINX

- **Base image:** `debian:bullseye-slim`
- **Installed packages:** `nginx`, `openssl`
- **Role:** HTTPS entry point. All traffic goes through NGINX.
- **Port:** 443 (HTTPS)
- **TLS:** Self-signed certificate generated at **build time** (in Dockerfile).
- **What it does:**
  1. Serves static files (CSS, JS, images) directly from the shared volume.
  2. Passes `.php` requests to `wordpress:9000` (PHP-FPM).
  3. Config is fully static (no template substitution).
- **PID 1:** `nginx -g "daemon off;"` (via `CMD`)

### 4.2 WordPress (PHP-FPM)

- **Base image:** `debian:bookworm-slim`
- **Installed packages:** `php-fpm`, `php-mysql`, `php-xml`, `php-zip`, `wget`,
  `ca-certificates`, `netcat-openbsd`
- **Role:** Process PHP and serve the WordPress application.
- **Port:** 9000 (PHP-FPM, internal only)
- **What it does:**
  1. Waits for MariaDB to be reachable (polls `nc -z` on port 3306).
  2. Downloads WordPress using WP-CLI if not already present.
  3. Creates `wp-config.php` with database credentials.
  4. Installs WordPress (creates admin user, second user).
  5. Sets correct file ownership (`www-data`).
- **PID 1:** `php-fpm -F`

### 4.3 MariaDB

- **Base image:** `debian:bullseye`
- **Installed packages:** `mariadb-server`
- **Role:** Relational database for WordPress.
- **Port:** 3306 (MySQL protocol, internal only)
- **What it does:**
  1. Changes MariaDB bind-address from `127.0.0.1` to `0.0.0.0` via `sed`.
  2. On first run: runs `mariadbd --init-file` to create the database and users.
  3. On subsequent runs: skips init and starts `mariadbd` directly.
- **PID 1:** `mariadbd`

---

## 5. How containers communicate

```
                    Internet
                       │
                   (port 443)
                       │
                  ┌────▼────┐
                  │  NGINX  │  (nginx container)
                  └────┬────┘
                       │ TCP :9000
                  ┌────▼────────┐
                  │  WordPress  │  (wordpress container)
                  │  PHP-FPM    │
                  └────┬────────┘
                       │ TCP :3306
                  ┌────▼────┐
                  │ MariaDB │  (mariadb container)
                  └─────────┘
```

- NGINX talks to WordPress via **FastCGI** over TCP port 9000.
- WordPress talks to MariaDB via **MySQL protocol** over TCP port 3306.
- All three are on the same Docker bridge network called `inception`.
- Only NGINX's port 443 is published to the host. WordPress and MariaDB are
  not accessible from outside the Docker network.

---

## 6. Volumes and data persistence

### 6.1 What data needs to persist?

1. **WordPress files** — uploads, plugins, themes, `wp-config.php`
2. **MariaDB data** — all database tables (posts, users, settings)

### 6.2 How it works in this project

Two named volumes are defined in `docker-compose.yml`:

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/mariadb
```

This is a **bind-mounted named volume**: it behaves like a Docker named volume
(appears in `docker volume ls`) but the actual data lives at a specific path on
the host (`/home/moham/data/wordpress` and `/home/moham/data/mariadb`).

The `DATA_PATH` variable comes from the `.env` file.

### 6.3 Who mounts what?

| Volume           | Mounted in                  | Mount point           |
|------------------|-----------------------------|-----------------------|
| `wordpress_data` | `wordpress` AND `nginx`     | `/var/www/html`       |
| `mariadb_data`   | `mariadb`                   | `/var/lib/mysql`      |

The `wordpress_data` volume is shared between WordPress and NGINX so NGINX can
directly serve static files (images, CSS, JS) without going through PHP.

### 6.4 When is data deleted?

- `make down` — containers are removed, volumes **remain**.
- `make clean` — containers, images, network removed, volumes **remain**.
- `make fclean` — containers, images, network, volumes, and the host data
  directories are **all deleted**. Use with caution.

---

## 7. Secrets and environment variables

### 7.1 Philosophy

**Secrets** (passwords) are never hard-coded in Dockerfiles, scripts, or the
compose file. They are stored in separate files under `secrets/` and mounted
into containers at runtime as **Docker secrets** (available as files under
`/run/secrets/`).

**Non-secret configuration** (domain name, database name, usernames) goes in
the `.env` file and is passed to containers via `env_file`.

### 7.2 Secret files

```
secrets/
├── db_password.txt          # One line: password for wp_user MariaDB user
├── db_root_password.txt     # One line: password for MariaDB root user
└── credentials.txt          # Line 1: WordPress admin password
                             # Line 2: WordPress editor password
```

These files are **excluded from git** via `.gitignore`. The repository only
contains a `.gitkeep` placeholder to keep the directory tracked.

### 7.3 How secrets are used

In `docker-compose.yml`:

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt
```

Then in the service definition:

```yaml
services:
  mariadb:
    secrets:
      - db_password
```

Inside the container, the secret content is available at `/run/secrets/db_password`.

In bash scripts:

```bash
DB_PASSWORD="$(cat /run/secrets/db_password)"
```

### 7.4 Why not environment variables for secrets?

Environment variables can be:
- Leaked through `docker inspect`, logs, error messages
- Inherited by child processes
- Accidentally committed to version control

Docker secrets (files) are more secure because:
- They are mounted as `tmpfs` (in-memory) filesystem
- They are only accessible by the exact container that needs them
- They are never visible in `docker inspect`

---

## 8. The .env file explained

**File:** `srcs/.env`

### What is a .env file?

A `.env` file is a plain text file containing key-value pairs. Docker Compose
automatically reads it (when placed next to the compose file) and makes those
variables available for:

- **Variable substitution** in `docker-compose.yml` (e.g., `${DATA_PATH}`)
- **Environment variables** inside containers (via `env_file:`)

### Our .env file

```env
DOMAIN_NAME=moham.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

WP_TITLE=Inception
WP_ADMIN_USER=siteowner
WP_ADMIN_EMAIL=siteowner@moham.42.fr
WP_USER=editor
WP_USER_EMAIL=editor@moham.42.fr

DATA_PATH=/home/moham/data
```

### Each variable explained

| Variable | Purpose | Used in |
|----------|---------|---------|
| `DOMAIN_NAME` | The domain where WordPress will be accessible | NGINX config template (`server_name`), WordPress install URL |
| `MYSQL_DATABASE` | Name of the database to create | MariaDB init SQL (`CREATE DATABASE`) |
| `MYSQL_USER` | MariaDB application user (not root) | MariaDB init SQL (`CREATE USER`) |
| `WP_TITLE` | WordPress site title | `wp core install --title` |
| `WP_ADMIN_USER` | WordPress administrator username | `wp core install --admin_user` |
| `WP_ADMIN_EMAIL` | WordPress admin email | `wp core install --admin_email` |
| `WP_USER` | Second WordPress user (editor role) | `wp user create` |
| `WP_USER_EMAIL` | Second user's email | `wp user create` |
| `DATA_PATH` | Host path for bind-mounted volumes | Volume `device:` paths in compose file |

### Why not hardcode these?

Portability. If someone else clones the project, they just edit `.env` to match
their own domain, login, and preferences — no need to touch any scripts or
config files.

---

## 9. TLS / SSL — what it is and why we use it

### 9.1 What is TLS?

**TLS** (Transport Layer Security) — formerly called **SSL** (Secure Sockets
Layer) — is a cryptographic protocol that provides **privacy** and **data
integrity** between two communicating applications (like a browser and a web
server).

### 9.2 How TLS works (simplified)

1. **Handshake:** Client connects to server. Server presents its **TLS
   certificate** (a digital identity document).
2. **Certificate verification:** Client checks that the certificate is:
   - Signed by a trusted **Certificate Authority** (CA)
   - Valid for the domain being accessed
   - Not expired or revoked
3. **Key exchange:** Client and server agree on a **session key** using
   asymmetric encryption (the server's public/private key pair).
4. **Encrypted communication:** From this point on, all data is encrypted with
   the session key (symmetric encryption, which is fast).

### 9.3 Why use TLS for this project?

1. **Confidentiality:** Without TLS, all traffic (including login passwords)
   travels in plain text over the network. Anyone on the same network can
   capture it with tools like Wireshark.

2. **Data integrity:** TLS ensures data is not modified in transit (man-in-the-
   middle attacks).

3. **Subject requirement:** The Inception project explicitly requires NGINX to
   serve over TLSv1.2 or TLSv1.3 only.

4. **Real-world practice:** Production websites use HTTPS (HTTP over TLS) by
   default. This project mirrors real-world setup.

### 9.4 Self-signed vs CA-signed certificate

- **CA-signed:** A trusted third party (like Let's Encrypt, DigiCert) verifies
  your identity and signs your certificate. Browsers trust it automatically.
- **Self-signed:** You create and sign the certificate yourself. Browsers show
  a warning ("Your connection is not private") because no CA verified it. **We
  use a self-signed certificate** in this project because:
  - We are on a local network / VM with no public domain
  - Getting a real CA certificate requires a public domain and validation
  - The subject does not require a real certificate

### 9.5 How the certificate is generated

In `srcs/requirements/nginx/Dockerfile` (at **build time**):

```bash
RUN openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -days 365 \
    -subj "/C=JO/ST=Amman/L=Amman/O=42/OU=Inception/CN=moham.42.fr"
```

Breaking this down:

| Flag | Meaning |
|------|---------|
| `req -x509` | Generate a self-signed X.509 certificate |
| `-nodes` | No DES — private key is NOT encrypted (required so NGINX can read it without a passphrase at startup) |
| `-days 365` | Valid for 1 year |
| `-newkey rsa:2048` | Generate a new 2048-bit RSA key pair |
| `-keyout` | Where to save the private key |
| `-out` | Where to save the certificate |
| `-subj` | Certificate subject (owner identity). `CN` (Common Name) must match the domain |

### 9.6 NGINX TLS configuration

```nginx
listen 443 ssl;
ssl_certificate     /etc/nginx/ssl/inception.crt;
ssl_certificate_key /etc/nginx/ssl/inception.key;
ssl_protocols       TLSv1.2 TLSv1.3;
```

- `listen 443 ssl;` — listen on port 443 with SSL/TLS enabled
- `ssl_protocols TLSv1.2 TLSv1.3;` — only accept modern, secure protocol
  versions (not the broken SSLv3, TLSv1.0, TLSv1.1)

The cipher list is left at OpenSSL's default (`DEFAULT@SECLEVEL=1`), which
already excludes anonymous ciphers and broken algorithms on Debian.

---

## 10. NGINX in detail

### 10.1 Dockerfile

```dockerfile
FROM debian:bullseye-slim

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
```

**What each line does:**

| Instruction | Purpose |
|-------------|---------|
| `FROM debian:bullseye-slim` | Start from a minimal Debian image |
| `RUN apt install nginx openssl` | Install the NGINX web server and OpenSSL |
| `RUN mkdir -p /etc/nginx/ssl` | Create directory for TLS certificate and key |
| `COPY conf/nginx.conf /etc/nginx/conf.d/default.conf` | Copy the static NGINX config into the `conf.d` directory (auto-included by NGINX) |
| `RUN rm -f /etc/nginx/sites-enabled/default` | Remove the default NGINX site to avoid conflicts |
| `RUN openssl req -x509 ...` | Generate a self-signed TLS certificate at **build time** (one-time, embedded in the image) |
| `EXPOSE 443` | Document that the container listens on port 443 |
| `CMD ["nginx", "-g", "daemon off;"]` | Start NGINX in the foreground as PID 1 |

**Key differences from a more complex approach:**
- No entrypoint script (`setup.sh` was removed) — the Dockerfile generates the
  cert at build time and uses `CMD` directly.
- No `envsubst` / `gettext-base` — the domain is hardcoded in the config file.
  This works because `moham.42.fr` never changes for this project.
- Config goes to `/etc/nginx/conf.d/` (auto-included) instead of
  `sites-available` + symlink.

### 10.2 NGINX config (`nginx.conf`)

```nginx
server {
    listen 443 ssl;
    server_name moham.42.fr;

    ssl_certificate     /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root  /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass  wordpress:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include       fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
```

**Explanation of each directive:**

| Directive | Meaning |
|-----------|---------|
| `listen 443 ssl;` | Listen on port 443, enable SSL/TLS |
| `server_name moham.42.fr;` | Respond only to requests for this domain (hardcoded) |
| `root /var/www/html;` | Serve files from this directory |
| `index index.php index.html;` | Default files to serve when a directory is requested |
| `location /` | For any URL, try the exact file first, then the directory, then pass to `index.php` |
| `try_files $uri $uri/ /index.php?$args` | NGINX tries: exact file → directory listing → WordPress front controller |
| `location ~ \.php$` | Match URLs ending in `.php` |
| `fastcgi_pass wordpress:9000;` | Forward PHP requests to the `wordpress` container on port 9000 |
| `fastcgi_param SCRIPT_FILENAME ...` | Tell PHP-FPM which file to execute |
| `location ~ /\.ht` | Block access to `.htaccess` and similar hidden files |

**Why `try_files $uri $uri/ /index.php?$args`?** This is the standard
WordPress configuration. WordPress uses a "front controller" pattern: all
requests are routed through `index.php`. If someone visits
`/2024/01/my-post/`, NGINX tries to find that exact file (doesn't exist), then
that directory (doesn't exist), then falls back to `/index.php?/2024/01/my-post/`
which WordPress interprets to show the correct post.

**Why no `ssl_ciphers` directive?** Removing it lets NGINX use OpenSSL's
built-in default cipher list (`DEFAULT@SECLEVEL=1`), which already excludes
anonymous ciphers and broken algorithms. This simplifies the config while
remaining secure.

---

## 11. MariaDB in detail

### 11.1 Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends mariadb-server \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/mysqld && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

COPY tools/init_db.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init_db.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init_db.sh"]
```

**Key points:**
- We only install `mariadb-server` (not `mariadb-client`). The client is not
  needed on the server container (WordPress has its own client).
- `/var/run/mysqld` is created and owned by `mysql` so the socket file can be
  written there.
- We chown `/var/lib/mysql` to `mysql` before the volume is mounted, so the
  base permissions are correct.
- No custom `50-server.cnf` — the default config is modified at runtime via
  `sed` in the entrypoint script.

### 11.2 Entrypoint script (`init_db.sh`)

```bash
#!/bin/bash
set -e

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

DB_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

sed -i "s/127.0.0.1/0.0.0.0/" "/etc/mysql/mariadb.conf.d/50-server.cnf"

if [ ! -d /var/lib/mysql/init ]; then
    cat > /tmp/init.sql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
    mkdir -p /var/lib/mysql/init
    exec mariadbd --user=mysql --datadir=/var/lib/mysql --init-file=/tmp/init.sql
fi

exec mariadbd --user=mysql --datadir=/var/lib/mysql
```

**Step by step:**

1. **Runtime setup** — Creates `/run/mysqld` (for the socket file) and ensures
   it is owned by the `mysql` user.

2. **Read secrets** — Passwords are read from Docker secrets files.

3. **`sed` bind-address** — Changes `bind-address` from `127.0.0.1` to
   `0.0.0.0` in the default config file. This is necessary because WordPress
   connects over the network from a different container. Without this, MariaDB
   would only accept connections from localhost via Unix socket.
   No custom config file needed — the default Debian `/etc/mysql/mariadb.conf.d/50-server.cnf`
   is patched in place.

4. **First-run check (`/var/lib/mysql/init`)** — This marker directory is
   created after the first successful initialisation. If it exists, we skip
   the initialisation entirely.

5. **Init SQL file** — Written to `/tmp/init.sql` and passed to `mariadbd`
   via `--init-file`. The SQL:
   - Sets the root password
   - Creates the WordPress database
   - Creates the application user (`wp_user`) with access from any host (`'%'`)
   - Grants all privileges on the WordPress database to that user
   - Flushes privileges

6. **`exec mariadbd --init-file`** — Starts MariaDB directly with the init SQL.
   On an empty data directory, `mariadbd` automatically bootstraps the system
   tables, executes the init SQL, and then serves normally. The `exec` replaces
   the shell so `mariadbd` becomes PID 1.

7. **Subsequent runs** — `/var/lib/mysql/init` exists on the persistent volume,
   so it skips the init block and just runs `exec mariadbd` directly.

**Why `mariadbd` and not `mysqld_safe`?** `mariadbd` is the actual MariaDB
server binary. `mysqld_safe` is a wrapper that restarts the server if it
crashes and logs to syslog. In a Docker container, restart logic is handled by
Docker itself (`restart: unless-stopped` in the compose file), so the wrapper
is unnecessary. Running `mariadbd` directly is simpler and the standard pattern
for MariaDB in Docker.

### 11.3 The SQL in detail

```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY 'root_password';
```
Sets a password for the MariaDB root user. Without this, root can connect
without a password (using Unix socket authentication).

```sql
CREATE DATABASE IF NOT EXISTS wordpress;
```
Creates the database where WordPress will store all its data (posts, users,
comments, options, etc.).

```sql
CREATE USER IF NOT EXISTS 'wp_user'@'%' IDENTIFIED BY 'password';
```
Creates a database user named `wp_user` that can connect from **any host**
(`@'%'`). This is WordPress's database user (not the root user). WordPress
will use these credentials to connect.

```sql
GRANT ALL PRIVILEGES ON wordpress.* TO 'wp_user'@'%';
```
Gives `wp_user` full permissions on the `wordpress` database only. It cannot
access other databases (like `mysql` system tables).

```sql
FLUSH PRIVILEGES;
```
Reloads the grant tables so all changes take effect immediately without
restarting.

---

## 12. WordPress + PHP-FPM in detail

### 12.1 Dockerfile

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update  \
    && apt-get install -y --no-install-recommends netcat-openbsd php-fpm php-mysql php-xml php-zip wget ca-certificates \
    && wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && rm -rf /var/lib/apt/lists/*
COPY tools/wordpress.sh .
RUN php wp-cli.phar --info
RUN chmod +x wp-cli.phar
RUN mv wp-cli.phar /usr/local/bin/wp
RUN chmod +x wordpress.sh

ENTRYPOINT ["./wordpress.sh"]
```

**Why each package?**

| Package | Purpose |
|---------|---------|
| `php-fpm` | PHP-FastCGI Process Manager — runs PHP as a service that NGINX can talk to (versionless, resolves to the Debian default PHP — 8.2 on bookworm) |
| `php-mysql` | PHP extension for connecting to MySQL/MariaDB |
| `php-xml` | PHP XML parser (WordPress uses XML-RPC, RSS feeds) |
| `php-zip` | ZIP file handling (plugin/theme uploads) |
| `wget` | Downloads WP-CLI during build |
| `ca-certificates` | CA certificates for HTTPS downloads |
| `netcat-openbsd` | Contains `nc` for checking if MariaDB port is open |

Packages **not installed** that are commonly seen:
- `mariadb-client` — not needed; port check uses `nc` instead of `mysqladmin`
- `php-curl` — not explicitly needed; WordPress fallback works without it
- `php-mbstring` — included in the default PHP install on bookworm

**`php wp-cli.phar --info`** — This verifies that the PHAR (PHP Archive) is
valid and runnable. If the download was corrupted or the PHP version is
incompatible, this command will fail during the build instead of at runtime.

**No `WORKDIR`** — The default working directory is `/`. The script copies to
`/wordpress.sh` and `ENTRYPOINT ["./wordpress.sh"]` resolves to `/wordpress.sh`.
The script then `cd`s to `/var/www/html` at runtime to perform WordPress
operations there.

**No `EXPOSE`** — `EXPOSE` is documentation-only and not required for
functionality. The port 9000 is still reachable within the Docker network.

### 12.2 What is WP-CLI?

WP-CLI (`wp`) is a command-line tool for managing WordPress installations. It
can:
- Download WordPress core
- Create `wp-config.php`
- Install WordPress (create admin user, set title)
- Create additional users
- Manage plugins, themes, options

Without WP-CLI, you would need to run the WordPress web installer in a browser,
which is impractical in a Docker setup.

### 12.3 Entrypoint script (`wordpress.sh`)

```bash
#!/bin/bash
set -euo pipefail

cd /var/www/html

DB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(sed -n '1p' /run/secrets/credentials)"
WP_USER_PASSWORD="$(sed -n '2p' /run/secrets/credentials)"

sed -i 's/^listen = .*/listen = 9000/' /etc/php/*/fpm/pool.d/www.conf
mkdir -p /run/php

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

ln -sf /usr/sbin/php-fpm* /usr/local/bin/php-fpm
exec php-fpm -F
```

**Step by step:**

1. **`cd /var/www/html`** — Changes to the WordPress directory. Since the
   default working directory is `/` (no `WORKDIR` in Dockerfile), we must
   navigate to the volume-mounted WordPress directory.

2. **Read secrets** — Passwords are read from Docker secrets files.

3. **PHP-FPM config** — `sed` changes the listen directive from the default
   Unix socket to TCP port 9000. The glob `php/*/fpm` matches any PHP version
   directory (no hardcoded version). Also ensures `/run/php` exists.

4. **Wait for MariaDB** — Uses `nc -z mariadb 3306` (netcat) to check if port
   3306 is open. This is simpler than `mysqladmin ping` and doesn't require
   `mariadb-client`. The loop blocks until MariaDB is ready.

5. **Check if already installed** — `[ ! -f /var/www/html/wp-config.php ]`
   checks if WordPress has already been set up. This file persists in the
   shared volume. If it exists, we skip the installation block.

6. **WordPress installation** — Downloads core, creates `wp-config.php`,
   installs WordPress (creates admin + editor users), and fixes ownership.

7. **`ln -sf /usr/sbin/php-fpm* /usr/local/bin/php-fpm`** — Creates a symlink
   so the versionless `php-fpm` command works. On Debian bookworm the binary
   is `/usr/sbin/php-fpm8.2` (versioned). The symlink makes the command
   distribution-agnostic.

8. **`exec php-fpm -F`** — Starts PHP-FPM in the foreground (`-F` flag) as
   PID 1.

### 12.4 WordPress database connection

WordPress connects to MariaDB using the parameters in `wp-config.php`:

```php
define('DB_NAME', 'wordpress');
define('DB_USER', 'wp_user');
define('DB_PASSWORD', 'ChangeMe_DbUserPass!42');
define('DB_HOST', 'mariadb:3306');
```

The host `mariadb:3306` works because Docker DNS resolves the container name
`mariadb` to its internal IP address on the `inception` network.

---

## 13. The Makefile explained

```makefile
NAME        = inception
LOGIN       = moham
COMPOSE     = srcs/docker-compose.yml
DATA_PATH   = /home/$(LOGIN)/data

all: setup up

setup:
	@mkdir -p $(DATA_PATH)/wordpress
	@mkdir -p $(DATA_PATH)/mariadb
	@echo "Data directories ready at $(DATA_PATH)"

build:
	@docker compose -f $(COMPOSE) build

up: setup
	@docker compose -f $(COMPOSE) up -d --build

down:
	@docker compose -f $(COMPOSE) down

start:
	@docker compose -f $(COMPOSE) start

stop:
	@docker compose -f $(COMPOSE) stop

restart: down up

logs:
	@docker compose -f $(COMPOSE) logs -f

ps:
	@docker compose -f $(COMPOSE) ps

clean: down
	@docker system prune -af

fclean: clean
	@sudo rm -rf $(DATA_PATH)
	@docker volume rm srcs_wordpress_data srcs_mariadb_data 2>/dev/null || true

re: fclean all

.PHONY: all setup build up down start stop restart logs ps clean fclean re
```

### Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `NAME` | `inception` | Project name (for display) |
| `LOGIN` | `moham` | Your 42 login, used to construct the data path |
| `COMPOSE` | `srcs/docker-compose.yml` | Path to the compose file |
| `DATA_PATH` | `/home/moham/data` | Host directory for persistent volumes |

### Targets explained

| Target | What it does |
|--------|-------------|
| `all` | Runs `setup` then `up` — the default action |
| `setup` | Creates the host data directories for volumes. These must exist before Docker tries to bind-mount them |
| `build` | Builds all Docker images (without starting containers) |
| `up` | Creates data dirs (if missing), builds images, and starts containers in detached mode (`-d`) with `--build` to rebuild if Dockerfiles changed |
| `down` | Stops and removes containers, network (but **not** volumes/data) |
| `start` | Resumes previously stopped containers without recreating them |
| `stop` | Pauses containers without removing them |
| `restart` | `down` followed by `up` |
| `logs` | Streams logs from all containers (`-f` follows) |
| `ps` | Shows running containers with status |
| `clean` | `down` + `docker system prune -af` removes all unused containers, images, networks |
| `fclean` | `clean` + removes the host data directories (`sudo rm -rf`) + removes named volumes |
| `re` | `fclean` + `all` — full clean rebuild |

### Why `setup` creates directories before Docker?

Docker bind-mounts require the source directory to already exist. If
`/home/moham/data/wordpress` doesn't exist when Docker tries to create the
volume, it fails with "no such file or directory". The `setup` target ensures
the directories exist before Docker needs them.

---

## 14. docker-compose.yml explained line by line

```yaml
services:
```

### MariaDB service

```yaml
  mariadb:
    build: ./requirements/mariadb
    image: inception-mariadb
    container_name: mariadb
    env_file: .env
    secrets:
      - db_password
      - db_root_password
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - inception
    restart: unless-stopped
```

| Directive | Meaning |
|-----------|---------|
| `build: ./requirements/mariadb` | Build the image using the Dockerfile in this directory |
| `image: inception-mariadb` | Tag the built image as `inception-mariadb` |
| `container_name: mariadb` | The container will be named `mariadb` (used as hostname by other containers) |
| `env_file: .env` | Pass all variables from `.env` into the container's environment |
| `secrets: [db_password, db_root_password]` | Mount these Docker secrets as files in `/run/secrets/` |
| `volumes: [mariadb_data:/var/lib/mysql]` | Mount the named volume `mariadb_data` at `/var/lib/mysql` |
| `networks: [inception]` | Connect to the `inception` network |
| `restart: unless-stopped` | Automatically restart if the container crashes, unless manually stopped |

### WordPress service

```yaml
  wordpress:
    build: ./requirements/wordpress
    image: inception-wordpress
    container_name: wordpress
    env_file: .env
    secrets:
      - db_password
      - credentials
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception
    depends_on:
      - mariadb
    restart: unless-stopped
```

| Directive | Meaning |
|-----------|---------|
| `depends_on: [mariadb]` | Docker Compose will start `mariadb` before `wordpress` |
| `secrets: [db_password, credentials]` | WordPress needs the DB password and the admin/editor passwords |

### NGINX service

```yaml
  nginx:
    build: ./requirements/nginx
    image: inception-nginx
    container_name: nginx
    env_file: .env
    volumes:
      - wordpress_data:/var/www/html
    ports:
      - "443:443"
    networks:
      - inception
    depends_on:
      - wordpress
    restart: unless-stopped
```

| Directive | Meaning |
|-----------|---------|
| `ports: ["443:443"]` | Publish container port 443 to host port 443. This is how you access the site. |
| `depends_on: [wordpress]` | Start `wordpress` before `nginx` |
| `volumes: [wordpress_data:/var/www/html]` | Share the WordPress files so NGINX can serve static assets directly |

### Network

```yaml
networks:
  inception:
    driver: bridge
```

Creates a custom **bridge** network named `inception`. Containers on this
network can communicate using container names as hostnames. Bridge is the
default Docker network type — isolated from the host network stack.

### Volumes

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/mariadb
```

These create named volumes backed by host directories (bind mounts). The
`${DATA_PATH}` variable is substituted from the `.env` file.

### Secrets

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  credentials:
    file: ../secrets/credentials.txt
```

Defines Docker secrets backed by local files. The paths are relative to the
compose file's directory (`srcs/`), so `../secrets/` resolves to
`Inception/secrets/`.

---

## 15. Lifecycle of a request

### 15.1 Fresh start (first `make up`)

```
1. Makefile creates /home/moham/data/wordpress and /home/moham/data/mariadb

2. Docker Compose builds images:
   ├── inception-mariadb   (installs MariaDB, generates TLS cert at build time)
   ├── inception-wordpress  (installs PHP, WP-CLI)
   └── inception-nginx     (installs NGINX, OpenSSL, generates TLS cert at build time)

3. Docker creates the inception network

4. Docker creates the named volumes (bound to host directories)

5. MariaDB container starts:
   ├── sed changes bind-address to 0.0.0.0
   ├── /var/lib/mysql/init doesn't exist → runs init SQL via --init-file
   ├── mariadbd bootstraps system tables, executes init.sql, starts serving
   └── mariadbd runs as PID 1

6. WordPress container starts (after MariaDB is "up"):
   ├── sed changes PHP-FPM listen to TCP 9000
   ├── Waits for MariaDB port 3306 (nc -z)
   ├── Downloads WordPress core (wp-cli)
   ├── Creates wp-config.php
   ├── Installs WordPress (creates admin + editor users)
   └── php-fpm starts (PID 1)

7. NGINX container starts:
   ├── Config is already static (hardcoded domain)
   ├── TLS cert is already in the image (generated at build time)
   └── nginx starts (PID 1)

8. Site is accessible at https://moham.42.fr
```

### 15.2 Subsequent starts (`make up` after `make down`)

```
1. Volumes still have data from the previous run
2. MariaDB: /var/lib/mysql/init exists → skip initialisation, start mariadbd directly
3. WordPress: /var/www/html/wp-config.php exists → skip install, start php-fpm
4. NGINX: nothing to regenerate, nginx starts immediately
```

### 15.3 A user visits https://moham.42.fr

```
Browser                          NGINX :443         WordPress :9000     MariaDB :3306
   │                                │                    │                  │
   │── HTTPS request ──────────────►│                    │                  │
   │                                │                    │                  │
   │◄── TLS handshake (cert) ──────│                    │                  │
   │                                │                    │                  │
   │── Encrypted HTTP request ────►│                    │                  │
   │                                │                    │                  │
   │                                │ Is it a .php file?│                  │
   │                                │   No → serve       │                  │
   │                                │   static file      │                  │
   │                                │     directly       │                  │
   │                                │                    │                  │
   │                                │ Yes → proxy to ───►│                  │
   │                                │   wordpress:9000   │                  │
   │                                │                    │                  │
   │                                │                    │── SQL query ────►│
   │                                │                    │◄── result ───────│
   │                                │                    │                  │
   │◄── HTML response ─────────────│◄── PHP output ─────│                  │
   │                                │                    │                  │
```

### 15.4 Admin logs in at https://moham.42.fr/wp-admin/

```
1. Browser loads /wp-admin/ → NGINX → PHP-FPM → WordPress dispatches to
   wp-login.php
2. User enters credentials
3. WordPress validates against MariaDB `wp_users` table
4. On success: WordPress sets session cookies, redirects to /wp-admin/
5. All subsequent admin actions (create post, upload media, change settings)
   follow the same path: NGINX → PHP-FPM → WordPress → MariaDB
```

---

## 16. Security considerations

### 16.1 What we do right

1. **Principle of least privilege:** `wp_user` only has access to the
   `wordpress` database, not the `mysql` system database or any other.

2. **No hardcoded secrets:** All passwords are in separate files under
   `secrets/`, excluded from git, and mounted as Docker secrets.

3. **No anonymous users:** MariaDB anonymous users are removed.

4. **No test database:** The default `test` database is dropped.

5. **Only TLSv1.2+:** Older, broken protocol versions are explicitly disabled.

6. **Strong ciphers only:** Weak ciphers (anonymous, MD5) are excluded.

7. **Only one entry point:** Only NGINX port 443 is exposed. MariaDB and
   WordPress are invisible from outside.

8. **No debugging or info leaks:** NGINX `server_tokens` could be disabled to
   hide the version number (not configured here but good practice).

9. **PID 1 handling:** All services run as PID 1 in the foreground, so Docker
   can properly manage them (signals, restarts, etc.).

10. **`restart: unless-stopped`:** Containers automatically recover from
    crashes.

### 16.2 What could be improved

1. **Self-signed certificate:** In production, use Let's Encrypt or another CA.

2. **No rate limiting:** NGINX could be configured with `limit_req` to prevent
   brute-force attacks on the login page.

3. **No fail2ban:** There's no mechanism to block IP addresses after repeated
   failed login attempts.

4. **No database backups:** There's no automated backup of the MariaDB data
   directory.

5. **Root in containers:** Containers run as root. In production, you'd use
   `USER` directives in Dockerfiles to run as non-root users.

---

## Appendix A: Key commands reference

```bash
# Build and start everything
make

# View running containers
make ps

# Follow all logs
make logs

# Follow logs for one service
docker compose -f srcs/docker-compose.yml logs -f nginx

# Open a shell inside a running container
docker compose -f srcs/docker-compose.yml exec wordpress bash

# Stop everything (keeps data)
make down

# Full clean wipe
make fclean

# Full rebuild from scratch
make re

# Check data on host
ls -la /home/moham/data/wordpress/
ls -la /home/moham/data/mariadb/

# Inspect Docker volumes
docker volume inspect srcs_wordpress_data

# Check Docker network
docker network inspect srcs_inception

# Test the site with curl
curl -k https://moham.42.fr

# View the TLS certificate
openssl s_client -connect moham.42.fr:443 -servername moham.42.fr < /dev/null 2>/dev/null | openssl x509 -text | head -20
```

## Appendix B: Ports summary

| Port | Service | Protocol | Accessible from host? | Purpose |
|------|---------|----------|-----------------------|---------|
| 443  | NGINX   | HTTPS    | Yes                   | WordPress website |
| 9000 | PHP-FPM | FastCGI  | No (internal only)    | PHP processing |
| 3306 | MariaDB | MySQL    | No (internal only)    | Database |

## Appendix C: Files in this project

| File | Purpose |
|------|---------|
| `Makefile` | Entry point: setup, build, up, down, clean, re |
| `srcs/.env` | Non-secret config: domain, DB name, usernames, paths |
| `srcs/docker-compose.yml` | Orchestrates 3 services, network, volumes, secrets |
| `srcs/requirements/mariadb/Dockerfile` | Builds MariaDB image (`debian:bullseye` + `mariadb-server`) |
| `srcs/requirements/mariadb/tools/init_db.sh` | Entrypoint: patches bind-address, init DB via `--init-file`, starts `mariadbd` |
| `srcs/requirements/wordpress/Dockerfile` | Builds PHP image (`debian:bookworm-slim` + PHP 8.2 + WP-CLI) |
| `srcs/requirements/wordpress/tools/wordpress.sh` | Entrypoint: configures PHP-FPM for TCP, waits for DB, installs WordPress, starts `php-fpm` |
| `srcs/requirements/nginx/Dockerfile` | Builds NGINX image (`debian:bullseye-slim` + nginx + openssl, generates TLS cert at build time) |
| `srcs/requirements/nginx/conf/nginx.conf` | Static NGINX virtual host config (hardcoded domain, TLSv1.2/1.3, proxy to wordpress:9000) |
| `secrets/db_password.txt` | MariaDB application user password (gitignored) |
| `secrets/db_root_password.txt` | MariaDB root password (gitignored) |
| `secrets/credentials.txt` | WordPress admin (line 1) and editor (line 2) passwords (gitignored) |
