# User Documentation

This document is for anyone who wants to use the Inception stack as an end
user or as the WordPress site administrator — no development knowledge
required.

## 1. What services does this stack provide?

| Service     | Role                                                            |
|-------------|------------------------------------------------------------------|
| NGINX       | The only entry point to the site, served over HTTPS on port 443. |
| WordPress   | The website itself, including its admin/back-office panel.       |
| MariaDB     | The database that stores all WordPress content (internal only).  |

You never talk to WordPress or MariaDB directly — everything goes through
NGINX on port 443.

## 2. Starting and stopping the project

From the root of the repository:

```sh
make            # build the images (if needed) and start everything
make stop       # pause all containers without removing them
make start      # resume previously stopped containers
make down       # stop and remove the containers (data is kept)
```

Check that everything is running with:

```sh
make ps
```

You should see three containers (`nginx`, `wordpress`, `mariadb`) with a
status of `Up`.

## 3. Accessing the website and the admin panel

- Public website: `https://student.42.fr`
- Administration panel (back office): `https://student.42.fr/wp-admin`

Replace `student` with the actual login configured in `srcs/.env`
(`DOMAIN_NAME`). The certificate is self-signed, so your browser will show a
security warning the first time — this is expected for a local project and
you can safely proceed.

## 4. Locating and managing credentials

Credentials are never stored in the code itself. They live in the
`secrets/` folder at the repository root, as plain text files that are
excluded from git:

- `secrets/credentials.txt` — line 1: WordPress administrator password,
  line 2: second WordPress user's password.
- `secrets/db_password.txt` — password of the WordPress database user.
- `secrets/db_root_password.txt` — password of the MariaDB root user.

The corresponding usernames (WordPress admin username, database username,
etc.) are set as plain configuration values in `srcs/.env`, since usernames
are not considered sensitive.

To change a password, edit the relevant file in `secrets/` and recreate the
affected container(s), e.g.:

```sh
make down
make up
```

Note: changing `secrets/credentials.txt` after the first WordPress install
will not retroactively change the password inside WordPress, since the
installation only happens once (on first run, when the data volume is
empty). To actually rotate a password afterwards, change it from the
WordPress admin panel directly, or reset the persisted volume with
`make fclean` (this wipes all site data) and run `make` again.

## 5. Checking that the services are running correctly

- `make ps` — shows the status (`Up`/`Exit`) and restart count of each
  container.
- `make logs` — streams the logs of all three containers; look for
  `[init_db] Starting MariaDB`, `[wp_setup] Starting php-fpm`, and
  `[nginx setup] Starting nginx` to confirm each service reached its
  running state.
- Visiting `https://student.42.fr` in a browser and seeing the WordPress
  homepage (rather than a connection error or a PHP error page) is the
  simplest end-to-end health check.
