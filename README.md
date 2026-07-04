# MyDockersScripts

Shell commands for creating and running LAMP development stacks on Docker.

One **project** = one Docker Compose stack with a shared MariaDB and phpMyAdmin.
Each **subproject** inside it gets its own Apache+PHP container (any PHP version),
its own source folder and its own database — so you can run e.g. four PrestaShop
versions side by side against one database server.

Everything a project needs is generated from the [templates/](templates/) folder,
and every generated project is a git repository of its own: each command commits
its changes, `data/` (MySQL data) and `*_src/` (your application code) stay ignored.

## Requirements

- Docker (with Compose v2, i.e. `docker compose`)
- git
- zsh or bash

## Installation

Clone into your home directory:

```sh
git clone https://github.com/AhcoOy/MyDockersScripts.git "$HOME/MyDockersScripts"
```

In `.zshrc` (or any favorite shell rc file) add:

```sh
################################ include all .sh files from MyDockersScripts folder
ZSH_HOME="$HOME/MyDockersScripts"
for file in "$ZSH_HOME"/*.sh; do
    [ -f "$file" ] && source "$file"
done
```

Open a new terminal (or `source ~/.zshrc`) and the commands below are available.

> Note: every `*.sh` file in this folder gets sourced at shell startup —
> keep only function-defining scripts here, never directly executable ones.

## Commands

| Command | Purpose |
|---|---|
| `myDockersCreate <Project> <SubProject> <HTTP_PORT> <MYSQL_PORT> <PMA_PORT> [PHP_IMAGE]` | Create a new project with its first subproject |
| `myDockersAdd <Project> <SubProject> [PHP_IMAGE]` | Add another web container to an existing project (HTTP port auto-detected) |
| `myDockersBuild <Project>` | Build all services, one log per service in `build_logs/` |
| `myDockersInitDBs <Project>` | Run all `mariadb/init/*.sql` and verify every database exists |
| `myDockersHints <Project>` | Cheat sheet of docker commands for a project |

`PHP_IMAGE` is any official `php:*-apache` image and defaults to `php:8.4-apache`.
Old images (down to PHP 7.1) work too: the Dockerfile template installs
everything it can and prints `WARNING:` lines for what it can't.

## Use case

Four PrestaShop versions in one stack:

```sh
# create the project with its first subproject
# (HTTP, MySQL and phpMyAdmin ports)
myDockersCreate myshop ps91 8601 8602 8603 php:8.5-apache

# add more subprojects, each with its own PHP version
myDockersAdd myshop ps8_last    php:8.1-apache
myDockersAdd myshop ps_1_7_last php:7.2-apache
myDockersAdd myshop ps_1_6_last php:7.1-apache

# build all images — logs land in ~/MyDockers/myshop/build_logs/
myDockersBuild myshop

# start the stack
cd "$HOME/MyDockers/myshop" && docker compose up -d

# create the databases and users (idempotent, verifies the result)
myDockersInitDBs myshop

# handy docker commands for daily work
myDockersHints myshop
```

Then:

- `http://localhost:8601` — first subproject (the others picked 8604, 8605, ... automatically)
- `http://localhost:8603` — phpMyAdmin, logged in as the project user, which
  has access to every subproject database
- put your code into `~/MyDockers/myshop/<php_id>_<subproject>_src/`

## Generated project layout

```
~/MyDockers/myshop/
├── docker-compose.yml
├── .gitignore                     # data/ and *_src/ ignored
├── apache/vhost.conf
├── build_logs/                    # one log per service + summary, per build run
├── data/mysql/                    # MariaDB data (ignored by git)
├── home/myshop/                   # shared home dir, mounted into web containers
├── mariadb/
│   ├── Dockerfile
│   ├── my.cnf
│   ├── initDb.sh
│   └── init/init-<db>.sql         # one per subproject
├── php85apache_ps91_web/          # build context (Dockerfile) per subproject
└── php85apache_ps91_src/          # your application code (ignored by git)
```

Naming, for a project `myshop` with subproject `ps91` on `php:8.5-apache`:

- compose service: `php85apache-ps91-web`
- container: `myshop_ps91_web` (db: `myshop_db`, phpMyAdmin: `myshop_phpmyadmin`)
- database / db user / db password: `php85apache_ps91`
- the web container gets `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` as environment variables

## Notes

- All generated files come from [templates/](templates/) — edit the templates to
  change what future projects look like.
- MariaDB root password is `root`; the project user (also the phpMyAdmin login)
  is `<Project>` / `<Project>` and is granted access to every subproject database.
- `myDockersBuild` and `myDockersInitDBs` keep going after a failure and report
  what failed at the end (build failures also land in the project's git history).
- After editing these scripts, re-source them (or open a new terminal) —
  functions already loaded in a shell keep their old code.

## Security

These stacks are for **local development only**. Credentials are fixed and
well-known (`root`/`root`, `<Project>`/`<Project>`), there is no TLS, and the
published ports have no access control. Never expose them to the internet or
run them on a shared host.

## License

[MIT](LICENSE) © Ahco Oy

