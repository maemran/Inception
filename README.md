*This project has been created as part of the 42 curriculum by student.*

# Inception

## Description

Inception is a system administration project whose goal is to build a small,
self-contained web infrastructure using Docker and Docker Compose, with each
service running in its own container built from a hand-written Dockerfile.

The stack provides a WordPress site served over HTTPS, made up of three
mandatory services:

- **NGINX** — the single entry point of the infrastructure, listening on port
  443 with TLSv1.2/TLSv1.3 only, and proxying PHP requests to WordPress.
- **WordPress + php-fpm** — the application layer, with no embedded web
  server (NGINX talks to it over FastCGI on port 9000).
- **MariaDB** — the database layer used by WordPress.

Two named Docker volumes persist the WordPress files and the MariaDB data on
the host, under `/home/student/data`, and a dedicated Docker network connects
the three containers. Credentials are never hard-coded: they are passed
through environment variables (`.env`) and Docker secrets.

## Instructions

### Prerequisites
- A Linux virtual machine with Docker and the Docker Compose plugin installed.
- A local entry in `/etc/hosts` mapping `student.42.fr` to `127.0.0.1` (replace
  `student` with your own login, consistently, everywhere it appears in this
  project: `.env`, `docker-compose.yml`, `Makefile`, secrets, etc.).

### Setup
1. Fill in real values in `secrets/db_password.txt`, `secrets/db_root_password.txt`
   and `secrets/credentials.txt` (see `secrets/.gitkeep` for the expected format).
   These files are git-ignored on purpose and must never be committed.
2. Adjust `srcs/.env` if needed (domain name, database name, WordPress admin
   username/email, etc.).
3. From the repository root, run:
   ```sh
   make
   ```
   This creates the host data directories, builds the three images and starts
   the containers in the background.
4. Visit `https://student.42.fr` in your browser (accept the self-signed
   certificate warning) to see the WordPress site, and
   `https://student.42.fr/wp-admin` to access the administration panel.

### Useful commands
```sh
make down      # stop and remove the containers
make logs      # follow the logs of all services
make ps        # show container status
make clean     # remove containers/images/network (keeps data)
make fclean    # also wipe the persisted data on the host
make re        # fclean + all
```

See `USER_DOC.md` and `DEV_DOC.md` for more detailed usage and development
instructions.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [WP-CLI documentation](https://wp-cli.org/)
- [WordPress Codex — Editing wp-config.php](https://wordpress.org/documentation/article/editing-wp-config-php/)
- ["About PID 1" — why containers shouldn't run hacky infinite-loop entrypoints](https://github.com/Yelp/dumb-init)

### AI usage

An AI assistant (Claude) was used during this project as a learning aid, not
as a substitute for understanding the material. Concretely, it was used to:

- Draft an initial skeleton of the `docker-compose.yml`, the three
  `Dockerfile`s and their entrypoint shell scripts, based on the subject's
  exact requirements (one service per container, named volumes, Docker
  network, secrets, TLS-only NGINX, etc.).
- Generate first drafts of this `README.md`, `USER_DOC.md` and `DEV_DOC.md`
  so the documentation structure matched the subject's requirements.
- Explain unfamiliar concepts encountered along the way (PID 1 and why
  `tail -f`/`sleep infinity` style entrypoints are discouraged, the
  difference between Docker secrets and environment variables, and how
  `wp-cli` automates a WordPress installation).

Every generated script and configuration file was then reviewed line by
line, tested by actually building and running the stack, and adjusted where
the generated output didn't match the subject's constraints or didn't behave
as expected (in particular the MariaDB/WordPress first-run initialisation
logic and the NGINX TLS configuration). Passwords and other secrets used in
this repository are local placeholders only and are excluded from git via
`.gitignore`.

## Project description: Docker design choices

All three services are built from the **penultimate stable release of
Debian** (`debian:bullseye` at the time of writing — adjust the base image
tag if a newer "penultimate stable" version is current when you build this).
No service runs more than one process in the foreground: each container's
entrypoint script performs first-run initialisation if needed, then
`exec`s the real daemon (`mysqld_safe`, `php-fpm7.4 -F`, `nginx -g "daemon
off;"`) so that it runs as PID 1 and receives signals correctly — no
`tail -f`, `sleep infinity`, or bare `bash` hacks.

### Virtual Machines vs Docker
A virtual machine virtualises an entire hardware stack and runs a full guest
operating system with its own kernel, which makes it heavier to start, to
duplicate and to scale, but gives very strong isolation. A Docker container
shares the host kernel and only packages the application and its
dependencies, which makes it much lighter and faster to start/stop, easier
to reproduce identically across machines, and a better fit for running
several small, single-purpose services side by side — at the cost of a
slightly weaker isolation boundary than a full VM.

### Secrets vs Environment Variables
Environment variables (here stored in `srcs/.env`) are convenient for
non-sensitive configuration (domain name, database name, usernames) because
they're easy to read and override, but they end up visible in `docker
inspect`, in process listings inside the container, and potentially in logs.
Docker secrets are mounted as read-only files under `/run/secrets/` inside
the container, are never part of the container's environment or image
layers, and are therefore the appropriate place for passwords (the
MariaDB root/user passwords and the WordPress account passwords in this
project).

### Docker Network vs Host Network
With `network: host`, a container shares the host's network namespace
directly: no isolation, no DNS-based service discovery between containers,
and a higher exposure surface, which is why the subject forbids it. The
custom bridge network created here (`inception`) gives each container its
own network namespace, lets them resolve each other by service name
(`mariadb`, `wordpress`, `nginx`), and only exposes the one port that needs
to be reachable from outside the host: 443 on the NGINX container.

### Docker Volumes vs Bind Mounts
A bind mount maps an arbitrary host path directly into a container and is
fully managed by the host filesystem, which makes permissions and portability
harder to control. A named volume is managed by the Docker daemon itself,
has a well-defined lifecycle independent of any single container, and is the
mechanism explicitly required by the subject for the WordPress files and the
MariaDB data — here configured (via `driver_opts`) to physically store their
data under `/home/student/data` on the host while still being manipulated as
proper Docker volumes (`docker volume ls/inspect`, etc.).
