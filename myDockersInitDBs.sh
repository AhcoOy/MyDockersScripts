
# db-engine helpers: one thin wrapper per operation
#   mariadb   the project's <Project>_db container
#   postgres  the project's <Project>_postgres_db container
#   hostdb    this machine's own MariaDB (LAlMP), shared by every such project;
#             the container argument is ignored

_myDockersDbExec() {    # <engine> <container>, sql from stdin
    local engine="$1" container="$2"
    case "$engine" in
        mariadb)  docker exec -i "$container" mariadb -uroot -proot ;;
        postgres) docker exec -i "$container" psql -U "${container%_postgres_db}" -d postgres -v ON_ERROR_STOP=1 ;;
        hostdb)   _myDockersHostDb ;;
    esac
}

_myDockersDbQuery() {   # <engine> <container> <query>, result rows only
    local engine="$1" container="$2" query="$3"
    case "$engine" in
        mariadb)  docker exec "$container" mariadb -uroot -proot -N -e "$query" ;;
        postgres) docker exec "$container" psql -U "${container%_postgres_db}" -d postgres -tA -c "$query" ;;
        hostdb)   _myDockersHostDb -N -e "$query" ;;
    esac
}

_myDockersDbExists() {  # <engine> <container> <dbname>
    local engine="$1" container="$2" db="$3"
    case "$engine" in
        mariadb|hostdb)
            _myDockersDbQuery "$engine" "$container" "SHOW DATABASES LIKE '$db';" 2>/dev/null \
                | grep -qx "$db"
            ;;
        postgres)
            _myDockersDbQuery postgres "$container" "SELECT datname FROM pg_database WHERE datname = '$db';" 2>/dev/null \
                | grep -qx "$db"
            ;;
    esac
}

_myDockersDbList() {    # <engine> <container>
    local engine="$1" container="$2"
    case "$engine" in
        mariadb)
            _myDockersDbQuery mariadb "$container" "SHOW DATABASES;" 2>/dev/null \
                | grep -vxE 'information_schema|performance_schema|mysql|sys'
            ;;
        postgres)
            _myDockersDbQuery postgres "$container" "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY datname;" 2>/dev/null
            ;;
    esac
}


# --- the host's MariaDB (LAlMP) --------------------------------------------
# Admin login, in this order:
#   1. whatever plain `mariadb` gets: ~/.my.cnf [client] section, or the
#      unix-socket login as yourself (Homebrew MariaDB on the Mac)
#   2. the same over TCP 127.0.0.1 — root@localhost and root@127.0.0.1 are
#      separate accounts and often have different passwords or plugins
#   3. a prompt for user + password, kept for this one command in a mode-600
#      temp file (the password never lands in the project or shell history)

_myDockersHostDb() {    # mariadb client args, as the admin from _myDockersHostDbLogin
    if [ -n "${_MYDOCKERS_HOSTDB_CNF:-}" ]; then
        mariadb --defaults-extra-file="$_MYDOCKERS_HOSTDB_CNF" "$@"
    elif [ -n "${_MYDOCKERS_HOSTDB_TCP:-}" ]; then
        mariadb -h 127.0.0.1 --skip-ssl "$@"
    else
        mariadb "$@"
    fi
}

_myDockersHostDbLogin() {
    _MYDOCKERS_HOSTDB_CNF=""
    _MYDOCKERS_HOSTDB_TCP=""

    command -v mariadb >/dev/null 2>&1 || {
        echo "ERROR: no mariadb client on this machine — LAlMP projects use the"
        echo "       host's own MariaDB server and need its client."
        return 1
    }

    mariadb -N -e "SELECT 1;" >/dev/null 2>&1 && return 0
    _MYDOCKERS_HOSTDB_TCP=1
    _myDockersHostDb -N -e "SELECT 1;" >/dev/null 2>&1 && return 0
    _MYDOCKERS_HOSTDB_TCP=""

    local user pw
    echo "Log in to this machine's MariaDB as an admin (one that can create"
    echo "databases and users; to skip this prompt put a [client] section in"
    echo "~/.my.cnf, chmod 600)."
    printf "MariaDB admin user [root]: "
    read -r user || { echo; return 1; }
    user="${user:-root}"
    printf "Password for %s@127.0.0.1: " "$user"
    read -rs pw || { echo; return 1; }
    echo

    _MYDOCKERS_HOSTDB_CNF=$(umask 077 && mktemp "${TMPDIR:-/tmp}/mydockers-hostdb.XXXXXX") || return 1
    {
        echo "[client]"
        printf 'user="%s"\n'     "$(printf '%s' "$user" | sed 's/[\\"]/\\&/g')"
        printf 'password="%s"\n' "$(printf '%s' "$pw"   | sed 's/[\\"]/\\&/g')"
        echo "host=127.0.0.1"
        echo "skip-ssl"
    } > "$_MYDOCKERS_HOSTDB_CNF"

    if ! _myDockersHostDb -N -e "SELECT 1;" >/dev/null 2>&1; then
        echo "ERROR: cannot log in to the host MariaDB as $user@127.0.0.1:"
        _myDockersHostDb -N -e "SELECT 1;" 2>&1 | sed 's/^/    /'
        _myDockersHostDbLogout
        return 1
    fi
    return 0
}

_myDockersHostDbLogout() {
    [ -n "${_MYDOCKERS_HOSTDB_CNF:-}" ] && rm -f "$_MYDOCKERS_HOSTDB_CNF"
    _MYDOCKERS_HOSTDB_CNF=""
    _MYDOCKERS_HOSTDB_TCP=""
}

# Can containers reach the host MariaDB? Tested from a throwaway container,
# so the bind address and the firewall are both covered. Prints the fix.
_myDockersHostDbReach() {   # <gateway ip>
    local gw="$1"

    docker run --rm alpine nc -zw3 "$gw" 3306 >/dev/null 2>&1 && return 0

    echo "WARNING: containers cannot reach this machine's MariaDB at $gw:3306."
    if [ "$(uname -s)" = Darwin ] || [ "$gw" != "${gw#192.168.65.}" ]; then
        echo "  Docker Desktop forwards the host gateway to the host's loopback:"
        echo "  MariaDB must listen on 127.0.0.1 (the default of a local install)."
        return 1
    fi
    echo "  MariaDB must also listen on Docker's bridge address. Add $gw to"
    echo "  bind-address (comma-separated, MariaDB 10.11+), e.g. in"
    echo "  /etc/mysql/mariadb.conf.d/z99-docker-bind.cnf:"
    echo "      [mysqld]"
    echo "      bind-address = 127.0.0.1,$gw"
    echo "  Currently configured:"
    grep -rhs '^ *bind-address' /etc/mysql/ 2>/dev/null | sed 's/^ */      /' \
        || echo "      (no bind-address line found under /etc/mysql)"
    echo "  $gw only exists while Docker runs, so start MariaDB after it:"
    echo "      sudo mkdir -p /etc/systemd/system/mariadb.service.d"
    echo "      printf '[Unit]\\nAfter=docker.service\\n' | sudo tee /etc/systemd/system/mariadb.service.d/z99-after-docker.conf"
    echo "      sudo systemctl daemon-reload && sudo systemctl restart mariadb"
    return 1
}


### run all <db>/init/*.sql of a project against its databases,
### verify every database really exists afterwards.
### supports mariadb (<Project>_db), postgres (<Project>_postgres_db) and
### hostdb (this machine's MariaDB, LAlMP projects)
myDockersInitDBs() {

    if [ $# -ne 1 ]; then
        echo "Usage:"
        echo "    myDockersInitDBs <Project>"
        echo
        echo "Example:"
        echo "    myDockersInitDBs ahco_ps"
        return 1
    fi

    local PROJECT="$1"
    local ROOT="$HOME/MyDockers/$PROJECT"

    if [ ! -d "$ROOT" ]; then
        echo "ERROR: project not found:"
        echo "    $ROOT"
        return 1
    fi

    local engine INIT_DIR DB_CONTAINER
    local sql_file db_name output i up gw found="" failed=""

    for engine in mariadb postgres hostdb; do

        INIT_DIR="$ROOT/$engine/init"
        [ -d "$INIT_DIR" ] || continue
        found=1

        case "$engine" in
            mariadb)  DB_CONTAINER="${PROJECT}_db" ;;
            postgres) DB_CONTAINER="${PROJECT}_postgres_db" ;;
            hostdb)   DB_CONTAINER="" ;;
        esac

        if [ "$engine" = hostdb ]; then
            echo "== hostdb (this machine's MariaDB) =="

            if ! _myDockersHostDbLogin; then
                echo "    Run again once the host MariaDB login works:  myDockersInitDBs $PROJECT"
                failed="$failed hostdb(no-login)"
                continue
            fi
        else
            echo "== $engine ($DB_CONTAINER) =="

            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
                echo "    Skipping: container $DB_CONTAINER is not running."
                echo "    Run again once the stack is up:  myDockersInitDBs $PROJECT"
                failed="$failed $engine(container-not-running)"
                continue
            fi

            # wait until the server answers stably before feeding it SQL
            # (on first boot the entrypoint runs a temporary server, then
            # restarts into the real one)
            up=""
            for i in $(seq 1 30); do
                if _myDockersDbQuery "$engine" "$DB_CONTAINER" "SELECT 1;" >/dev/null 2>&1; then
                    sleep 2
                    _myDockersDbQuery "$engine" "$DB_CONTAINER" "SELECT 1;" >/dev/null 2>&1 && up=1 && break
                fi
                sleep 1
            done

            if [ -z "$up" ]; then
                echo "    ERROR: cannot connect to $engine in $DB_CONTAINER as root."
                echo "    Check:"
                echo "        docker logs $DB_CONTAINER"
                failed="$failed $engine(no-connection)"
                continue
            fi
        fi

        for sql_file in "$INIT_DIR"/*.sql; do
            [ -e "$sql_file" ] || continue

            echo "Running $sql_file"

            if ! output=$(_myDockersDbExec "$engine" "$DB_CONTAINER" < "$sql_file" 2>&1); then
                echo "    ERROR: sql failed:"
                echo "$output" | sed 's/^/        /'
                failed="$failed $(basename "$sql_file")"
                continue
            fi

            # verify the database from init-<db>.sql really exists
            db_name=$(basename "$sql_file" .sql)
            db_name="${db_name#init-}"

            if _myDockersDbExists "$engine" "$DB_CONTAINER" "$db_name"; then
                echo "    OK: database $db_name exists"
            else
                echo "    ERROR: database $db_name is missing after running the sql"
                failed="$failed $db_name"
            fi
        done

        if [ "$engine" = hostdb ]; then
            _myDockersHostDbLogout
            # the server is shared: list nothing else, but check that the
            # containers will get through to it
            gw=$(awk '$2 == "db" && $1 ~ /^[0-9.]+$/ { print $1; exit }' \
                    "$ROOT/mounted_shared_etc/hosts" 2>/dev/null)
            if [ -n "$gw" ]; then
                _myDockersHostDbReach "$gw" || failed="$failed hostdb(unreachable-from-containers)"
            fi
        else
            echo "Databases on $DB_CONTAINER:"
            _myDockersDbList "$engine" "$DB_CONTAINER" | sed 's/^/    /'
        fi
        echo
    done

    if [ -z "$found" ]; then
        echo "ERROR: no database init folders (mariadb/init, postgres/init, hostdb/init) found in:"
        echo "    $ROOT"
        return 1
    fi

    if [ -n "$failed" ]; then
        echo "FAILED:$failed"
        return 1
    fi

    echo "All databases OK."
}
