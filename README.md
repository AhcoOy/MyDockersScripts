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
| `myDockersCreate <Project> <SubProject> <HTTP_PORT> <DB_PORT> <ADMIN_PORT> [PHP_IMAGE] [TEMPLATES]` | Create a new project with its first subproject |
| `myDockersAdd <Project> <SubProject> [PHP_IMAGE] [TEMPLATE]` | Add another web container to an existing project (HTTP port auto-detected) |
| `myDockersBuild <Project>` | Build all services, one log per service in `build_logs/` |
| `myDockersInitDBs <Project>` | Run all `mariadb/init/*.sql` and verify every database exists |
| `myDockersHints [Project] [SubProject]` | List all projects, or a cheat sheet of docker commands for one |

`PHP_IMAGE` is any official `php:*-apache` image and defaults to `php:8.4-apache`.
Old images (down to PHP 7.1) work too: the Dockerfile template installs
everything it can and prints `WARNING:` lines for what it can't.

## Template sets

`TEMPLATES` names a folder under [templates/](templates/) and defaults to `LAMP`:

| Set | Stack |
|---|---|
| `LAMP` | Apache + PHP, **MariaDB**, phpMyAdmin |
| `LAPP` | Apache + PHP, **PostgreSQL** (container `<Project>_postgres_db`), Adminer |

```sh
myDockersCreate mylapp shop 8701 8702 8703 php:8.4-apache LAPP
```

The chosen set is stored in the project's `.myDockersTemplate` file, and
`myDockersAdd` renders new subprojects from that same set automatically.
For an old project without the marker file, `myDockersAdd` defaults to `LAMP`
only if the project actually is one — otherwise it asks you to pass the
template explicitly: `myDockersAdd <Project> <SubProject> <PHP_IMAGE> <TEMPLATE>`.

Rendering is driven by what a template set contains: every file in the set is
rendered with its relative path preserved (`<db>/init.sql` becomes the
per-subproject `<db>/init/init-<db_name>.sql`, `*.sh` files are made
executable, and `data/` folders are created only for the databases present).
To create your own set, copy a folder under `templates/` and edit away —
it becomes a valid `TEMPLATES` value immediately.

## Use case 1

Four PrestaShop versions on one LAMP stack, MariaDB + phpMyAdmin
(runnable script: [examples/useCase.sh](examples/useCase.sh)):

```sh
# create the project with its first subproject
# (HTTP, database and phpMyAdmin ports)
myDockersCreate myLampPrj ps91 8611 8612 8613 php:8.5-apache

# add more subprojects, each with its own PHP version
myDockersAdd myLampPrj ps8_last    php:8.1-apache
myDockersAdd myLampPrj ps_1_7_last php:7.2-apache
myDockersAdd myLampPrj ps_1_6_last php:7.1-apache

# build all images — logs land in ~/MyDockers/myLampPrj/build_logs/
myDockersBuild myLampPrj

# start the stack
cd "$HOME/MyDockers/myLampPrj" && docker compose up -d

# create the databases and users (idempotent, verifies the result)
myDockersInitDBs myLampPrj

# handy docker commands for daily work
myDockersHints myLampPrj
```

Then:

- `http://localhost:8611` — first subproject (the others picked 8614, 8615, ... automatically)
- `http://localhost:8613` — phpMyAdmin, logged in as the project user, which
  has access to every subproject database
- MariaDB listens on `localhost:8612`, container `myLampPrj_db`
- put your code into `~/MyDockers/myLampPrj/<php_id>_<subproject>_src/`

## Use case 2, with PostgreSQL

The same flow on a LAPP stack — just name the template set
(runnable script: [examples/useCase2.sh](examples/useCase2.sh)):

```sh
# create the project with its first subproject
# (HTTP, database and Adminer ports)
myDockersCreate myLappPrj php82web 8601 8602 8603 php:8.5-apache LAPP

# add more subprojects, each with its own PHP version
myDockersAdd myLappPrj php71web php:7.1-apache LAPP

# build all images — logs land in ~/MyDockers/myLappPrj/build_logs/
myDockersBuild myLappPrj

# start the stack
cd "$HOME/MyDockers/myLappPrj" && docker compose up -d

# create the databases and users (idempotent, verifies the result)
myDockersInitDBs myLappPrj

# handy docker commands for daily work
myDockersHints myLappPrj
```

Then:

- `http://localhost:8601` / `http://localhost:8604` — the two subprojects
- `http://localhost:8603/?pgsql=pgdb&username=myLappPrj&db=myLappPrj` — Adminer
  login with everything preselected; password `myLappPrj`. The project user is
  the PostgreSQL superuser, and subproject users like `php85apache_php82web`
  work too (`myDockersCreate` prints this URL ready-made)
- PostgreSQL listens on `localhost:8602`, container `myLappPrj_postgres_db`
- databases: one per subproject, e.g. `php85apache_php82web` /
  `php71apache_php71web` (user and password are the same as the name)
- put your code into `~/MyDockers/myLappPrj/<php_id>_<subproject>_src/`

## Generated project layout

```
~/MyDockers/myshop/
├── docker-compose.yml
├── .gitignore                     # data/ and *_src/ ignored
├── build_logs/                    # one log per service + summary, per build run
├── data/mysql/                    # MariaDB data (ignored by git)
├── home/myshop/                   # shared home dir, mounted into web containers
├── mariadb/
│   ├── Dockerfile
│   ├── my.cnf
│   ├── initDb.sh
│   └── init/init-<db>.sql         # one per subproject
├── mounted_etc/ps91/              # per-subproject config, mounted into that container
│   ├── vhost.conf                 #   -> /etc/apache2/sites-available/000-default.conf
│   └── php.ini                    #   -> /usr/local/etc/php/conf.d/zz-mydockers.ini
├── mounted_shared_etc/
│   └── hosts                      # all hostnames + static IPs, -> /etc/hosts in every service
├── php85apache_ps91_web/          # build context (Dockerfile) per subproject
└── php85apache_ps91_src/          # your application code (ignored by git)
```

Naming, for a project `myshop` with subproject `ps91` on `php:8.5-apache`:

- compose service: `php85apache-ps91-web`
- container: `myshop_ps91_web` (db: `myshop_db`, phpMyAdmin: `myshop_phpmyadmin`)
- database / db user / db password: `php85apache_ps91`
- the web container gets `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` as environment variables

### Network: static IPs and hostnames

Every project gets its own subnet — `myDockersCreate` picks the next free
`172.30.N.0/24` across all projects, and `myDockersAdd` reuses it (projects
created before this feature get the network block added on their next
`myDockersAdd`). Inside the project every service has a static IP and a
hostname:

- database (`db` / `pgdb`): `.10`, phpMyAdmin / Adminer: `.11`
- web services: `.101`, `.102`, ... in the order they were added
- each web container's hostname is its subproject name (`ps91`), which is
  also a network alias — containers reach each other with plain
  `http://ps91/` or via the static IP
- `mounted_shared_etc/hosts` lists every hostname with its static IP and is
  mounted as `/etc/hosts` into **every** service, so all containers resolve
  each other even without Docker's DNS. Each entry carries comments showing
  exactly how to reach that service (ssh/curl from another container, URL
  and db client from your machine, `docker exec` for a shell)
- the hosts file is regenerated on every `myDockersAdd`, but only above its
  marker line — add your own entries below the marker and they are kept

Per-subproject config lives in `mounted_etc/<subproject>/` — edit `vhost.conf`
or `php.ini` there and restart just that container.

### SSH between containers

Every web container runs an SSH server next to Apache, and there is no
firewall between containers on the project network — from any container you
can reach any other by hostname, on any port:

```sh
docker exec -it myLampPrj_ps91_web bash

ssh myLampPrj@ps8_last        # password: myLampPrj (the project user)
curl http://ps_1_7_last/      # every web service answers on port 80
```

Because `/home/<Project>` is one shared folder mounted into all web
containers, an SSH key generated once (`ssh-keygen`) works between all of
them after `cat ~/.ssh/id_*.pub >> ~/.ssh/authorized_keys`. `sshpass` is
preinstalled for scripted password logins.

## Notes

- All generated files come from [templates/](templates/) — edit the templates to
  change what future projects look like.
- MariaDB root password is `root`; the project user (also the phpMyAdmin login)
  is `<Project>` / `<Project>` and is granted access to every subproject database.
  On LAPP the project user `<Project>` / `<Project>` *is* the PostgreSQL superuser.
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

