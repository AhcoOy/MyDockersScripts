
### run all mariadb/init/*.sql of a project against its db container,
### verify every database really exists afterwards
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
    local INIT_DIR="$ROOT/mariadb/init"
    local DB_CONTAINER="${PROJECT}_db"

    if [ ! -d "$INIT_DIR" ]; then
        echo "ERROR: init folder not found:"
        echo "    $INIT_DIR"
        return 1
    fi

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
        echo "Skipping DB init: container $DB_CONTAINER is not running."
        echo "Run it once the stack is up:"
        echo "    myDockersInitDBs $PROJECT"
        return 1
    fi

    # make sure the server answers before feeding it SQL
    if ! docker exec "$DB_CONTAINER" mariadb -uroot -proot -e "SELECT 1;" >/dev/null 2>&1; then
        echo "ERROR: cannot connect to MariaDB in $DB_CONTAINER as root."
        echo "Is the server still starting up? Check:"
        echo "    docker logs $DB_CONTAINER"
        return 1
    fi

    local sql_file db_name output found="" failed=""

    for sql_file in "$INIT_DIR"/*.sql; do
        [ -e "$sql_file" ] || continue
        found=1

        echo "Running $sql_file"

        if ! output=$(docker exec -i "$DB_CONTAINER" mariadb -uroot -proot < "$sql_file" 2>&1); then
            echo "    ERROR: sql failed:"
            echo "$output" | sed 's/^/        /'
            failed="$failed $(basename "$sql_file")"
            continue
        fi

        if [ -n "$output" ]; then
            echo "$output" | sed 's/^/    /'
        fi

        # verify the database from init-<db>.sql really exists
        db_name=$(basename "$sql_file" .sql)
        db_name="${db_name#init-}"

        if docker exec "$DB_CONTAINER" mariadb -uroot -proot -N \
            -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null | grep -qx "$db_name"; then
            echo "    OK: database $db_name exists"
        else
            echo "    ERROR: database $db_name is missing after running the sql"
            failed="$failed $db_name"
        fi
    done

    if [ -z "$found" ]; then
        echo "ERROR: no .sql files found in:"
        echo "    $INIT_DIR"
        return 1
    fi

    echo
    if [ -n "$failed" ]; then
        echo "FAILED:$failed"
        return 1
    fi

    echo "All databases OK. Databases on $DB_CONTAINER:"
    docker exec "$DB_CONTAINER" mariadb -uroot -proot -N -e "SHOW DATABASES;" 2>/dev/null \
        | grep -vxE 'information_schema|performance_schema|mysql|sys' \
        | sed 's/^/    /'
}
