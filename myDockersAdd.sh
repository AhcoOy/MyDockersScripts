
# Load shared helpers (normalizePhpImage, renderTemplate, myDockersCommit,
# myDockersInitDBs, MYDOCKERS_TEMPLATE_DIR)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersAddSource="${BASH_SOURCE[0]}"
else
    _myDockersAddSource="${(%):-%x}"
fi
_myDockersAddDir="$(cd "$(dirname "$_myDockersAddSource")" && pwd)"
source "$_myDockersAddDir/myDockersCreate.sh"
source "$_myDockersAddDir/myDockersInitDBs.sh"
unset _myDockersAddSource _myDockersAddDir


### add a new web container to an existing Docker LAMP project
myDockersAdd() {

    if [ $# -lt 2 ] || [ $# -gt 4 ]; then
        echo "Usage:"
        echo "    myDockersAdd <Project> <SubProject> [PHP_IMAGE] [TEMPLATE]"
        echo
        echo "Example:"
        echo "    myDockersAdd moduledev prestashop82 php:8.2-apache"
        echo "    myDockersAdd mylapp shop2 php:8.4-apache LAPP"
        return 1
    fi

    local PROJECT="$1"
    local SUB_PROJECT="$2"

    # Optional, default to the latest stable PHP Apache image
    local PHP_IMAGE="${3:-php:8.4-apache}"
    local TEMPLATE_ARG="${4:-}"
    local PHP_ID
    PHP_ID=$(normalizePhpImage "$PHP_IMAGE")

    local ROOT="$HOME/MyDockers/$PROJECT"
    local COMPOSE="$ROOT/docker-compose.yml"
    local CONTAINER="${PROJECT}_${SUB_PROJECT}_web"
    local WEB_DIR="${PHP_ID}_${SUB_PROJECT}_web"
    local SRC_DIR="${PHP_ID}_${SUB_PROJECT}_src"

    if [ ! -d "$ROOT" ]; then
        echo "Project does not exist:"
        echo "    $ROOT"
        return 1
    fi

    # use the template set the project was created with;
    # an explicit 4th parameter always wins and is remembered
    local TEMPLATE
    if [ -n "$TEMPLATE_ARG" ]; then
        TEMPLATE="$TEMPLATE_ARG"
    else
        TEMPLATE=$(cat "$ROOT/.myDockersTemplate" 2>/dev/null)

        if [ -z "$TEMPLATE" ]; then
            # no marker: only a mariadb project can safely default to LAMP
            if grep -q "_postgres_db" "$ROOT/docker-compose.yml" \
                || ! grep -q "mariadb" "$ROOT/docker-compose.yml"; then
                echo "Project $PROJECT is not a default LAMP setup, and has no"
                echo ".myDockersTemplate marker. Give all 4 parameters explicitly:"
                echo
                echo "    myDockersAdd $PROJECT $SUB_PROJECT $PHP_IMAGE LAPP"
                echo
                echo "Available templates:"
                ls -d "$MYDOCKERS_TEMPLATE_DIR"/*/ 2>/dev/null | sed -e 's|/$||' -e 's|.*/|    |'
                return 1
            fi
            TEMPLATE="LAMP"
        fi
    fi

    local TPL="$MYDOCKERS_TEMPLATE_DIR/$TEMPLATE"

    if [ ! -d "$TPL" ]; then
        echo "Templates folder not found:"
        echo "    $TPL"
        echo
        echo "Available templates:"
        ls -d "$MYDOCKERS_TEMPLATE_DIR"/*/ 2>/dev/null | sed -e 's|/$||' -e 's|.*/|    |'
        return 1
    fi

    echo "$TEMPLATE" > "$ROOT/.myDockersTemplate"

    if [ ! -f "$COMPOSE" ]; then
        echo "docker-compose.yml not found:"
        echo "    $COMPOSE"
        return 1
    fi

    if grep -q "container_name: $CONTAINER" "$COMPOSE"; then
        echo "Container $CONTAINER already exists in:"
        echo "    $COMPOSE"
        return 1
    fi

    if command -v docker >/dev/null 2>&1 \
        && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
        echo "Container $CONTAINER is already created in Docker."
        return 1
    fi

    # Next available host port: highest published port in
    # docker-compose.yml + 1
    local LAST_PORT
    LAST_PORT=$(grep -Eo '"[0-9]+:[0-9]+"' "$COMPOSE" | cut -d'"' -f2 | cut -d: -f1 | sort -n | tail -1)

    if [ -z "$LAST_PORT" ]; then
        echo "No published ports found in:"
        echo "    $COMPOSE"
        return 1
    fi

    local HTTP_PORT=$((LAST_PORT + 1))

    echo "Adding $CONTAINER ($PHP_IMAGE, http port $HTTP_PORT) to $ROOT"

    mkdir -p "$ROOT/$WEB_DIR" "$ROOT/$SRC_DIR"

    renderTemplate "$TPL/php/Dockerfile" > "$ROOT/$WEB_DIR/Dockerfile"

    # per-subproject database init file, for every db the template set has
    local sql initdir
    for sql in $(find "$TPL" -maxdepth 2 -name init.sql 2>/dev/null); do
        initdir="$ROOT/$(basename "$(dirname "$sql")")/init"
        mkdir -p "$initdir"
        renderTemplate "$sql" > "$initdir/init-${PHP_ID}_${SUB_PROJECT}.sql"
    done

    renderTemplate "$TPL/web-service.yml" >> "$COMPOSE"

    touch "$ROOT/$SRC_DIR/index.php"

    myDockersInitDBs "$PROJECT"

    myDockersCommit "$ROOT" "myDockersAdd $SUB_PROJECT ($PHP_IMAGE, $TEMPLATE)"

    echo
    echo "Done."
    echo
    echo "Next:"
    echo "    myDockersBuild $PROJECT"
    echo "    cd $ROOT && docker compose up -d"
    echo "    myDockersInitDBs $PROJECT"
}
