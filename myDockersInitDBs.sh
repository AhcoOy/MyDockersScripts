
# db-engine helpers: one thin wrapper per operation

_myDockersDbExec() {    # <engine> <container>, sql from stdin
    local engine="$1" container="$2"
    case "$engine" in
        mariadb)  docker exec -i "$container" mariadb -uroot -proot ;;
        postgres) docker exec -i "$container" psql -U "${container%_postgres_db}" -d postgres -v ON_ERROR_STOP=1 ;;
    esac
}

_myDockersDbQuery() {   # <engine> <container> <query>, result rows only
    local engine="$1" container="$2" query="$3"
    case "$engine" in
        mariadb)  docker exec "$container" mariadb -uroot -proot -N -e "$query" ;;
        postgres) docker exec "$container" psql -U "${container%_postgres_db}" -d postgres -tA -c "$query" ;;
    esac
}

_myDockersDbExists() {  # <engine> <container> <dbname>
    local engine="$1" container="$2" db="$3"
    case "$engine" in
        mariadb)
            _myDockersDbQuery mariadb "$container" "SHOW DATABASES LIKE '$db';" 2>/dev/null \
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


### run all <db>/init/*.sql of a project against its database containers,
### verify every database really exists afterwards.
### supports mariadb (<Project>_db) and postgres (<Project>_postgres_db)
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
    local sql_file db_name output i up found="" failed=""

    for engine in mariadb postgres; do

        INIT_DIR="$ROOT/$engine/init"
        [ -d "$INIT_DIR" ] || continue
        found=1

        case "$engine" in
            mariadb)  DB_CONTAINER="${PROJECT}_db" ;;
            postgres) DB_CONTAINER="${PROJECT}_postgres_db" ;;
        esac

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

        echo "Databases on $DB_CONTAINER:"
        _myDockersDbList "$engine" "$DB_CONTAINER" | sed 's/^/    /'
        echo
    done

    if [ -z "$found" ]; then
        echo "ERROR: no database init folders (mariadb/init, postgres/init) found in:"
        echo "    $ROOT"
        return 1
    fi

    if [ -n "$failed" ]; then
        echo "FAILED:$failed"
        return 1
    fi

    echo "All databases OK."
}
