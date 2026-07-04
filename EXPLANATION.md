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
│       │   ├── conf/
│       │   │   └── 50-server.cnf     # MariaDB server configuration
│       │   └── tools/
│       │       └── init_db.sh        # Entrypoint: initialises DB, starts server
│       ├── wordpress/
│       │   ├── Dockerfile            # How to build the WordPress/PHP image
│       │   └── tools/
│       │       └── wp_setup.sh       # Entrypoint: waits for DB, installs WP, starts PHP-FPM
│       └── nginx/
│           ├── Dockerfile            # How to build the NGINX image
│           ├── conf/
│           │   └── nginx.conf  # NGINX virtual host config template
│           └── tools/
│               └── setup.sh          # Entrypoint: generates config, TLS cert, starts NGINX
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

- **Base image:** `debian:bullseye`
- **Installed packages:** `nginx`, `openssl`, `gettext-base`
- **Role:** HTTPS entry point. All traffic goes through NGINX.
- **Port:** 443 (HTTPS)
- **TLS:** Self-signed certificate generated on first start.
- **What it does:**
  1. Generates a self-signed SSL certificate with OpenSSL.
  2. Substitutes `${DOMAIN_NAME}` in the config template using `envsubst`.
  3. Serves static files (CSS, JS, images) directly from the shared volume.
  4. Passes `.php` requests to `wordpress:9000` (PHP-FPM).
- **PID 1:** `nginx -g "daemon off;"`

### 4.2 WordPress (PHP-FPM)

- **Base image:** `debian:bullseye`
- **Installed packages:** `php7.4-fpm`, `php7.4-mysql`, `php7.4-curl`,
  `php7.4-xml`, `php7.4-mbstring`, `php7.4-zip`, `curl`, `ca-certificates`,
  `mariadb-client`
- **Role:** Process PHP and serve the WordPress application.
- **Port:** 9000 (PHP-FPM, internal only)
- **What it does:**
  1. Waits for MariaDB to be reachable (polls `mysqladmin ping`).
  2. Downloads WordPress using WP-CLI if not already present.
  3. Creates `wp-config.php` with database credentials.
  4. Installs WordPress (creates admin user, second user).
  5. Sets correct file ownership (`www-data`).
- **PID 1:** `php-fpm7.4 -F`

### 4.3 MariaDB

- **Base image:** `debian:bullseye`
- **Installed packages:** `mariadb-server`
- **Role:** Relational database for WordPress.
- **Port:** 3306 (MySQL protocol, internal only)
- **What it does:**
  1. Initialises the database data directory with `mysql_install_db`.
  2. Starts a temporary server, runs SQL to create the database and users.
  3. Shuts down the temporary server and starts the real server.
- **PID 1:** `mysqld_safe`

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

In `srcs/requirements/nginx/tools/setup.sh`:

```bash
openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -subj "/C=JO/ST=Amman/L=Amman/O=42School/OU=Inception/CN=${DOMAIN_NAME}"
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
ssl_ciphers         HIGH:!aNULL:!MD5;
```

- `listen 443 ssl;` — listen on port 443 with SSL/TLS enabled
- `ssl_protocols TLSv1.2 TLSv1.3;` — only accept modern, secure protocol
  versions (not the broken SSLv3, TLSv1.0, TLSv1.1)
- `ssl_ciphers HIGH:!aNULL:!MD5;` — use strong ciphers, exclude anonymous
  ciphers and the broken MD5 algorithm

---

## 10. NGINX in detail

### 10.1 Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        openssl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl

COPY conf/nginx.conf /etc/nginx/sites-available/nginx.conf
COPY tools/setup.sh /usr/local/bin/setup.sh

RUN rm -f /etc/nginx/sites-enabled/default \
    && chmod +x /usr/local/bin/setup.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/setup.sh"]
```

**What each line does:**

| Instruction | Purpose |
|-------------|---------|
| `FROM debian:bullseye` | Start from the penultimate stable Debian release |
| `RUN apt-get install nginx` | Install the NGINX web server |
| `RUN ... install openssl` | Install OpenSSL to generate TLS certificates |
| `RUN ... install gettext-base` | Install `envsubst` for variable substitution in config |
| `mkdir -p /etc/nginx/ssl` | Create directory for TLS certificate and key |
| `COPY conf/...` | Copy the NGINX virtual host template into the image |
| `COPY tools/setup.sh` | Copy the entrypoint script |
| `rm -f /etc/nginx/sites-enabled/default` | Remove the default NGINX site |
| `EXPOSE 443` | Document that the container listens on port 443 |
| `ENTRYPOINT [...]` | Set the entrypoint script that runs when the container starts |

### 10.2 Entrypoint script (`setup.sh`)

```bash
#!/bin/bash
set -euo pipefail

envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/sites-available/nginx.conf \
    > /etc/nginx/sites-available/nginx.conf

ln -sf /etc/nginx/sites-available/nginx.conf /etc/nginx/sites-enabled/nginx.conf

if [ ! -f /etc/nginx/ssl/inception.crt ]; then
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=JO/ST=Amman/L=Amman/O=42School/OU=Inception/CN=${DOMAIN_NAME}"
fi

exec nginx -g "daemon off;"
```

**Step by step:**

1. **`set -euo pipefail`** — Bash safety options:
   - `-e`: exit immediately if any command fails
   - `-u`: treat unset variables as an error
   - `-o pipefail`: if any command in a pipeline fails, the whole pipeline fails

2. **`envsubst`** — reads the template file, replaces `${DOMAIN_NAME}` with its
   actual value from the environment, writes the result to the real config file.

3. **`ln -sf`** — creates a symbolic link from `sites-available` to
   `sites-enabled` (NGINX convention: `sites-available` holds all configs,
   `sites-enabled` holds only the active ones).

4. **Certificate generation** — only if it doesn't already exist (so it persists
   across container restarts if you mount the ssl directory).

5. **`exec nginx -g "daemon off;"`** — replaces the shell process with NGINX
   running in the foreground. This is critical: Docker containers stop when
   PID 1 exits. By using `exec`, NGINX becomes PID 1 and keeps the container
   alive. Without `daemon off;`, NGINX would fork to the background and the
   container would exit immediately.

### 10.3 NGINX config template

```nginx
server {
    listen 443 ssl;
    server_name ${DOMAIN_NAME};

    ssl_certificate     /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

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
| `server_name ${DOMAIN_NAME};` | Respond only to requests for this domain |
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

---

## 11. MariaDB in detail

### 11.1 Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
        mariadb-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/init_db.sh /usr/local/bin/init_db.sh

RUN chmod +x /usr/local/bin/init_db.sh \
    && mkdir -p /var/run/mysqld \
    && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init_db.sh"]
```

**Key points:**
- We only install `mariadb-server` (not `mariadb-client`). The client is not
  needed on the server container (WordPress has its own client).
- `/var/run/mysqld` is created and owned by `mysql` so the socket file can be
  written there.
- We chown `/var/lib/mysql` to `mysql` before/during the build step. The
  actual data will later be mounted from the volume, but the base permissions
  must be correct.

### 11.2 MariaDB config (`50-server.cnf`)

```ini
[mysqld]
user            = mysql
bind-address    = 0.0.0.0
port            = 3306
datadir         = /var/lib/mysql
socket          = /run/mysqld/mysqld.sock
pid-file        = /run/mysqld/mysqld.pid
skip-name-resolve
```

| Setting | Purpose |
|---------|---------|
| `user = mysql` | Run the MariaDB process as the `mysql` system user |
| `bind-address = 0.0.0.0` | Listen on **all** network interfaces (not just localhost). Required because WordPress connects over the network from a different container. Without this, MariaDB would only accept connections from the same machine via Unix socket. |
| `port = 3306` | Standard MySQL/MariaDB port |
| `datadir = /var/lib/mysql` | Where database files are stored (on the persisted volume) |
| `socket = /run/mysqld/mysqld.sock` | Unix socket file for local connections |
| `pid-file = /run/mysqld/mysqld.pid` | File containing the process ID |
| `skip-name-resolve` | Don't resolve client hostnames. Speeds up connections and avoids DNS issues. With this setting, you must use IP-based or `%` (wildcard) in user host grants. |

**Why `bind-address = 0.0.0.0`?** By default, MariaDB only listens on
`127.0.0.1` (localhost). This is secure for a local installation but prevents
other containers from connecting. Since WordPress runs in a separate container,
MariaDB must listen on all interfaces (`0.0.0.0`) — but only the Docker
internal network, so it's still not exposed to the outside world.

### 11.3 Entrypoint script (`init_db.sh`)

```bash
#!/bin/bash
set -euo pipefail

DB_PASSWORD="$(cat /run/secrets/db_password)"
DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

init_db() {
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
}

init_sql() {
    mysqld_safe --skip-networking --datadir=/var/lib/mysql &
    pid="$!"
    until mysqladmin ping --silent 2>/dev/null; do
        sleep 1
    done

    mysql -u root <<-EOSQL
        DELETE FROM mysql.user WHERE User='';
        DROP DATABASE IF EXISTS test;
        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --user=root --password="${DB_ROOT_PASSWORD}" shutdown
    wait "$pid"
}

if [ ! -d "/var/lib/mysql/mysql" ]; then
    init_db
    init_sql
elif [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    init_sql
fi

exec mysqld_safe --datadir=/var/lib/mysql
```

**Why this complex script?** MariaDB needs to be initialised before it can be
used. The first time the container runs:

1. **`mysql_install_db`** creates the initial database structure (system tables,
   default users) in the data directory. This only runs once.

2. **`mysqld_safe --skip-networking &`** starts a temporary MariaDB server with
   networking disabled (only accessible via Unix socket). We start it in the
   background (`&`) so we can run SQL commands.

3. **Wait loop:** `until mysqladmin ping` waits until the server is ready to
   accept connections.

4. **SQL commands:**
   - `DELETE FROM mysql.user WHERE User='';` — remove anonymous users (security)
   - `DROP DATABASE IF EXISTS test;` — remove the default test database (security)
   - `CREATE DATABASE ...` — create the WordPress database
   - `CREATE USER ...` — create the WordPress application user
   - `GRANT ALL PRIVILEGES ...` — give the user full access to the WordPress DB
   - `ALTER USER 'root'@'localhost' ...` — set the MariaDB root password
   - `FLUSH PRIVILEGES;` — apply all changes immediately

5. **`mysqladmin shutdown`** — stop the temporary server.

6. **`wait "$pid"`** — wait for the temporary server to fully shut down.

7. **`exec mysqld_safe`** — start the real MariaDB server in the foreground.

**The `elif` branch:** If the `mysql` system database exists (from a partial
init) but the `wordpress` database doesn't, we re-run the SQL. This handles
cases where the initialisation was interrupted.

**Why `mysqld_safe` and not `mysqld`?** `mysqld_safe` is a wrapper that:
- Launches `mysqld` (the actual server)
- Restarts it if it crashes
- Logs startup information to syslog

### 11.4 The SQL in detail

```sql
DELETE FROM mysql.user WHERE User='';
```
Removes anonymous user accounts. MariaDB creates an anonymous user by default
that allows anyone to connect without a password. This is a security risk.

```sql
DROP DATABASE IF EXISTS test;
```
Removes the default `test` database. Also a security risk.

```sql
CREATE DATABASE IF NOT EXISTS `wordpress`;
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
GRANT ALL PRIVILEGES ON `wordpress`.* TO 'wp_user'@'%';
```
Gives `wp_user` full permissions on the `wordpress` database only. It cannot
access other databases (like `mysql` system tables).

```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY 'root_password';
```
Sets a password for the MariaDB root user. Without this, root can connect
without a password (using Unix socket authentication).

```sql
FLUSH PRIVILEGES;
```
Reloads the grant tables so all changes take effect immediately without
restarting.

---

## 12. WordPress + PHP-FPM in detail

### 12.1 Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
        php7.4-fpm \
        php7.4-mysql \
        php7.4-curl \
        php7.4-xml \
        php7.4-mbstring \
        php7.4-zip \
        curl \
        ca-certificates \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

RUN sed -i 's/^listen = .*/listen = 9000/' /etc/php/7.4/fpm/pool.d/www.conf \
    && sed -i 's/^;\?listen\.owner.*/listen.owner = www-data/' /etc/php/7.4/fpm/pool.d/www.conf \
    && sed -i 's/^;\?listen\.group.*/listen.group = www-data/' /etc/php/7.4/fpm/pool.d/www.conf

RUN mkdir -p /run/php

COPY tools/wp_setup.sh /usr/local/bin/wp_setup.sh
RUN chmod +x /usr/local/bin/wp_setup.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wp_setup.sh"]
```

**Why each package?**

| Package | Purpose |
|---------|---------|
| `php7.4-fpm` | PHP-FastCGI Process Manager — runs PHP as a service that NGINX can talk to |
| `php7.4-mysql` | PHP extension for connecting to MySQL/MariaDB |
| `php7.4-curl` | PHP extension for HTTP requests (WordPress needs it for updates, API calls) |
| `php7.4-xml` | PHP XML parser (WordPress uses XML-RPC, RSS feeds) |
| `php7.4-mbstring` | Multibyte string support (internationalisation) |
| `php7.4-zip` | ZIP file handling (plugin/theme uploads) |
| `curl` | Command-line tool for downloading WP-CLI |
| `ca-certificates` | CA certificates for HTTPS downloads |
| `mariadb-client` | Contains `mysqladmin` and `mysql` CLI for waiting/checking DB |

**PHP-FPM config modification:**
```dockerfile
RUN sed -i 's/^listen = .*/listen = 9000/' /etc/php/7.4/fpm/pool.d/www.conf
```
By default, PHP-FPM listens on a Unix socket (`/run/php/php7.4-fpm.sock`).
This only works if NGINX and PHP are on the same machine. Since they are in
**separate containers**, we change it to listen on TCP port 9000 so NGINX can
connect over the Docker network.

```dockerfile
RUN mkdir -p /run/php
```
PHP-FPM needs the `/run/php` directory to exist for its PID file. Without this,
it fails with "Unable to create the PID file".

**WP-CLI download:**
```dockerfile
RUN curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp
```
Downloads the WP-CLI (WordPress Command Line Interface) tool during image
build. This allows us to install and configure WordPress from the command line
without a browser.

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

### 12.3 Entrypoint script (`wp_setup.sh`)

```bash
#!/bin/bash
set -euo pipefail

DB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(sed -n '1p' /run/secrets/credentials)"
WP_USER_PASSWORD="$(sed -n '2p' /run/secrets/credentials)"

until mysqladmin ping -h"mariadb" -u"${MYSQL_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; do
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

exec php-fpm7.4 -F
```

**Step by step:**

1. **Read secrets** — passwords are read from Docker secrets files.

2. **Wait for MariaDB** — The `until` loop runs `mysqladmin ping` connecting to
   the `mariadb` host. This blocks until MariaDB is ready to accept
   connections. Without this, WordPress would try to create its config and
   install before the database is ready, causing errors.

3. **Check if already installed** — `[ ! -f /var/www/html/wp-config.php ]`
   checks if WordPress has already been set up. This file is only created
   during installation and persists in the shared volume. If it exists, we
   skip the entire installation block.

4. **`wp core download --force`** — Downloads WordPress core files (the entire
   CMS source code) into `/var/www/html`. The `--force` flag overwrites any
   existing files (handles partial downloads).

5. **`wp config create`** — Generates `wp-config.php` with the database
   connection details. WordPress needs this file to know how to connect to the
   database.

6. **`wp core install`** — Runs the WordPress installation wizard from the
   command line. Creates the admin user, sets the site title, and configures
   the site URL.

7. **`wp user create`** — Creates a second user with the `editor` role.
   The subject requires at least two users.

8. **`chown -R www-data:www-data`** — Ensures all WordPress files are owned by
   the `www-data` user (the user that PHP-FPM runs as). Without this,
   WordPress might not be able to write to `wp-content/uploads` etc.

9. **`exec php-fpm7.4 -F`** — Starts PHP-FPM in the foreground (`-F` flag) as
   PID 1. The `-F` flag prevents PHP-FPM from daemonising.

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
   ├── inception-mariadb   (installs MariaDB from Debian packages)
   ├── inception-wordpress  (installs PHP, WP-CLI, configures PHP-FPM)
   └── inception-nginx     (installs NGINX, OpenSSL)

3. Docker creates the inception network

4. Docker creates the named volumes (bound to host directories)

5. MariaDB container starts:
   ├── mysql_install_db creates system tables
   ├── Temporary server starts
   ├── SQL: create database 'wordpress', user 'wp_user'@'%', set root password
   ├── Temporary server stops
   └── mysqld_safe starts (PID 1)

6. WordPress container starts (after MariaDB is "up"):
   ├── Waits for MariaDB to accept connections
   ├── Downloads WordPress core (wp-cli)
   ├── Creates wp-config.php
   ├── Installs WordPress (creates admin + editor users)
   └── php-fpm7.4 starts (PID 1)

7. NGINX container starts (after WordPress is "up"):
   ├── Generates nginx config from template (envsubst)
   ├── Generates self-signed TLS certificate
   └── nginx starts (PID 1)

8. Site is accessible at https://moham.42.fr
```

### 15.2 Subsequent starts (`make up` after `make down`)

```
1. Volumes still have data from the previous run
2. MariaDB: /var/lib/mysql/mysql exists → skip initialisation, start mysqld_safe
3. WordPress: /var/www/html/wp-config.php exists → skip install, start php-fpm
4. NGINX: config and cert exist → skip generation, start nginx
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

## Appendix C: Files modified in this project

| File | What changed |
|------|-------------|
| `srcs/.env` | `DATA_PATH=/home/moham/data`, `DOMAIN_NAME=moham.42.fr`, fixed emails |
| `srcs/docker-compose.yml` | Images renamed to `inception-*`, simplified structure |
| `srcs/requirements/mariadb/Dockerfile` | Removed `mariadb-client`, removed comments |
| `srcs/requirements/mariadb/tools/init_db.sh` | Reordered SQL (passwords last), added fallback for partial init |
| `srcs/requirements/mariadb/conf/50-server.cnf` | Unchanged (was already minimal) |
| `srcs/requirements/wordpress/Dockerfile` | Added `mkdir -p /run/php`, removed `php7.4-gd`, removed comments |
| `srcs/requirements/wordpress/tools/wp_setup.sh` | Added `--force` to `wp core download`, removed comments |
| `srcs/requirements/nginx/Dockerfile` | Removed comments |
| `srcs/requirements/nginx/tools/setup.sh` | Removed echo statements, removed comments |
| `srcs/requirements/nginx/conf/nginx.conf` | Unchanged |
