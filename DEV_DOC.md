# Developer Documentation

This document describes how to set up, build and work on the Inception
project from a development point of view.

## 1. Setting up the environment from scratch

### Prerequisites
- A Linux virtual machine (the project must run inside a VM, not directly on
  bare metal or in a container-in-container setup).
- Docker Engine and the Docker Compose v2 plugin (`docker compose version`
  should work).
- `make`.
- A local DNS entry so that `student.42.fr` (replace `student` with your
  login) resolves to the VM's own IP, e.g. by editing `/etc/hosts`:
  ```
  127.0.0.1   student.42.fr
  ```

### Configuration files to review before the first build
- `srcs/.env` — non-secret configuration: `DOMAIN_NAME`, `MYSQL_DATABASE`,
  `MYSQL_USER`, WordPress title/admin username/email/second user, and
  `DATA_PATH` (must point to `/home/<login>/data`).
- `secrets/db_password.txt`, `secrets/db_root_password.txt`,
  `secrets/credentials.txt` — create these with real values; they are
  git-ignored and must never be committed. See `secrets/.gitkeep` for the
  expected layout.

## 2. Building and launching the project

The `Makefile` at the repository root is the single entry point:

```sh
make            # setup host data dirs + build images + start containers
make build      # (re)build the images only, without starting them
make up         # start (and build if needed) the containers in the background
make down       # stop and remove the containers
```

Internally, `make` calls:

```sh
docker compose -f srcs/docker-compose.yml up -d --build
```

Each service has its own Dockerfile under
`srcs/requirements/<service>/Dockerfile`, built from `debian:bullseye`
(the penultimate stable Debian release at the time of writing). No
ready-made application images are pulled from Docker Hub; only the base
Debian image is used as a starting point, per the subject's rules.

### Container startup logic
Every entrypoint script follows the same pattern: on first run (detected by
checking whether the persisted volume already contains data — the MariaDB
data directory or `wp-config.php`), it performs one-time initialisation,
then replaces itself with the real foreground process via `exec`, so that
the daemon runs as PID 1 (`mariadbd`, `php-fpm -F`, `nginx -g "daemon
off;"`). There are no infinite-loop placeholder commands (`tail -f`,
`sleep infinity`, etc.) anywhere in the entrypoints.

## 3. Managing containers and volumes

```sh
make ps                                   # container status
make logs                                 # follow logs of all services
docker compose -f srcs/docker-compose.yml logs -f nginx   # logs of one service
docker compose -f srcs/docker-compose.yml exec wordpress bash  # shell into a container
docker volume ls                          # list named volumes (srcs_wordpress_data, srcs_mariadb_data)
docker volume inspect srcs_mariadb_data   # see the volume's host mountpoint
docker network ls                         # see the inception bridge network
```

`make clean` removes containers/images/the network (but keeps the named
volumes and their data). `make fclean` additionally deletes the data
persisted on the host. `make re` is `fclean` followed by `all`, i.e. a full
rebuild from a clean state.

## 4. Where project data is stored and how it persists

Two named Docker volumes are declared in `srcs/docker-compose.yml`:

- `wordpress_data` → mounted at `/var/www/html` in both the `wordpress` and
  `nginx` containers (so NGINX can serve static assets directly while PHP
  requests are proxied to php-fpm).
- `mariadb_data` → mounted at `/var/lib/mysql` in the `mariadb` container.

Both are configured with `driver_opts` (`type: none`, `o: bind`, `device:
${DATA_PATH}/...`) so that, while they remain proper Docker named volumes
(visible via `docker volume ls/inspect`, not raw bind mounts referenced
directly in the service's `volumes:` section), their actual data lives at
`/home/<login>/data/wordpress` and `/home/<login>/data/mariadb` on the host,
as required by the subject. This means the WordPress files and the
database survive `docker compose down`, container recreation, and even
`make down`/`make up` cycles — the data is only removed by `make fclean`,
which explicitly deletes `DATA_PATH`.
