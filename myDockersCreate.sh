
# Resolve the directory this script lives in (works when sourced from bash or zsh)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersScriptPath="${BASH_SOURCE[0]}"
else
    _myDockersScriptPath="${(%):-%x}"
fi
MYDOCKERS_TEMPLATE_DIR="$(cd "$(dirname "$_myDockersScriptPath")" && pwd)/templates"
unset _myDockesrScriptPath


# Re-source every myDockers script — run after editing them, so the
# functions in your open shell match the code on disk.
myDockersReload() {
    local dir f
    dir="$(dirname "$MYDOCKERS_TEMPLATE_DIR")"
    for f in "$dir"/*.sh; do
        [ -f "$f" ] && source "$f"
    done
    echo "myDockers commands reloaded from $dir"
}


# Check that the docker daemon is up and answering. A wedged daemon can
_myDockersDaemonCheck() {
    command -v docker >/dev/null 2>&1 || {
        echo "ERROR: docker command not found."
        return 1
    }

    docker info >/dev/null 2>&1 || {
        echo "ERROR: the docker daemon is not answering."
        echo
        echo "Restart Docker Desktop (whale menu > Restart), or from the terminal:"
        echo "    osascript -e 'quit app \"Docker Desktop\"' && open -a Docker"
        echo "Then wait until this works again:"
        echo "    docker info"
        return 1
    }
    return 0
}


normalizePhpImage() {
    local image="$1"

    # php:8.5-apache -> php85apache
    image="${image#php:}"
    image="${image//./}"
    image="${image//-/}"

    echo "php$image"
}


# Render a template file to stdout, replacing __PLACEHOLDER__ tokens.
# Relies on the caller's PROJECT/SUB_PROJECT/PHP_ID/PHP_IMAGE/*_PORT variables.
renderTemplate() {
    local template="$1"

    sed -e "s|__PROJECT__|$PROJECT|g" \
        -e "s|__SUB_PROJECT_ID__|$SUB_PROJECT|g" \
        -e "s|__PHP_ID__|$PHP_ID|g" \
        -e "s|__PHP_IMAGE__|$PHP_IMAGE|g" \
        -e "s|__HTTP_PORT__|$HTTP_PORT|g" \
        -e "s|__MYSQL_PORT__|$MYSQL_PORT|g" \
        -e "s|__PMA_PORT__|$PMA_PORT|g" \
        "$template"
}


# Make sure the project is a git repository (with .gitignore) and commit
# whatever has changed, on whatever branch is checked out.
myDockersCommit() {
    local root="$1"
    local message="$2"

    if ! command -v git >/dev/null 2>&1; then
        echo "WARNING: git not installed, skipping commit"
        return 0
    fi

    if [ ! -d "$root/.git" ]; then
        echo "Initializing git repository in $root"
        git -C "$root" init --quiet || { echo "WARNING: git init failed, skipping commit"; return 0; }
    fi

    if [ ! -f "$root/.gitignore" ]; then
        local tpl
        tpl=$(cat "$root/.myDockersTemplate" 2>/dev/null)
        cp "$MYDOCKERS_TEMPLATE_DIR/${tpl:-LAMP}/gitignore" "$root/.gitignore"
    fi

    git -C "$root" add -A

    if git -C "$root" diff --cached --quiet 2>/dev/null; then
        echo "git: nothing to commit"
        return 0
    fi

    if git -C "$root" commit --quiet -m "$message"; then
        echo "git: committed '$message'"
    else
        echo "WARNING: git commit failed"
    fi
}


### create new Docker project from a template set (default: LAMP)
myDockersCreate() {

    if [ $# -lt 5 ] || [ $# -gt 7 ]; then
        echo "Usage:"
        echo "    myDockersCreate <Project> <SubProject> <HTTP_PORT> <MYSQL_PORT> <PHPMYADMIN_PORT> [PHP_IMAGE] [TEMPLATES]"
        echo
        echo "Example:"
        echo "    myDockersCreate moduledev prestashop91 8890 8906 8902 php:8.5-apache"
        echo "    myDockersCreate myapp mysubproject 8080 3306 8081 php:8.4-apache LAPP"
        echo
        echo "Available templates:"
        ls -d "$MYDOCKERS_TEMPLATE_DIR"/*/ 2>/dev/null | sed -e 's|/$||' -e 's|.*/|    |'
        return 1
    fi

    local PROJECT="$1"
    local SUB_PROJECT="$2"
    local HTTP_PORT="$3"
    local MYSQL_PORT="$4"
    local PMA_PORT="$5"

    # Optional, default to the latest stable PHP Apache image
    local PHP_IMAGE="${6:-php:8.4-apache}"
    local PHP_ID
    PHP_ID=$(normalizePhpImage "$PHP_IMAGE")

    # Optional template set, a folder under templates/
    local TEMPLATE="${7:-LAMP}"
    local ROOT="$HOME/MyDockers/$PROJECT"
    local TPL="$MYDOCKERS_TEMPLATE_DIR/$TEMPLATE"
    local WEB_DIR="${PHP_ID}_${SUB_PROJECT}_web"
    local SRC_DIR="${PHP_ID}_${SUB_PROJECT}_src"

    if [ ! -d "$TPL" ]; then
        echo "Templates folder not found:"
        echo "    $TPL"
        echo
        echo "Available templates:"
        ls -d "$MYDOCKERS_TEMPLATE_DIR"/*/ 2>/dev/null | sed -e 's|/$||' -e 's|.*/|    |'
        return 1
    fi

    if [ -d "$ROOT" ]; then
        echo "Project already exists:"
        echo "    $ROOT"
        return 1
    fi

    echo "Creating $ROOT"

    # docker exec -it -u myproject myproject_web bash

    mkdir -p "$ROOT/home/$PROJECT" "$ROOT/$WEB_DIR" "$ROOT/$SRC_DIR"

    # data folders only for the databases this template set contains
    [ -d "$TPL/mariadb" ]  && mkdir -p "$ROOT/data/mysql"
    [ -d "$TPL/postgres" ] && mkdir -p "$ROOT/data/postgres"

    # remember the template set; myDockersAdd renders from the same one
    echo "$TEMPLATE" > "$ROOT/.myDockersTemplate"

    renderTemplate "$TPL/docker-compose.yml"  > "$ROOT/docker-compose.yml"
    renderTemplate "$TPL/web-service.yml"    >> "$ROOT/docker-compose.yml"
    renderTemplate "$TPL/php/Dockerfile"      > "$ROOT/$WEB_DIR/Dockerfile"

    # render every other file the template set contains, keeping paths
    local tfile dest
    for tfile in $(cd "$TPL" && find . -type f | sed 's|^\./||'); do
        case "$tfile" in
            gitignore|docker-compose.yml|web-service.yml|php/Dockerfile|*.DS_Store)
                continue
                ;;
        esac

        case "$tfile" in
            */init.sql)
                # per-subproject database init file
                dest="$ROOT/${tfile%/init.sql}/init/init-${PHP_ID}_${SUB_PROJECT}.sql"
                ;;
            *)
                dest="$ROOT/$tfile"
                ;;
        esac

        mkdir -p "$(dirname "$dest")"
        renderTemplate "$TPL/$tfile" > "$dest"

        case "$dest" in
            *.sh) chmod +x "$dest" ;;
        esac
    done

    touch "$ROOT/$SRC_DIR/index.php"

    myDockersCommit "$ROOT" "myDockersCreate $PROJECT $SUB_PROJECT ($PHP_IMAGE, $TEMPLATE)"

    echo
    echo "Done."
    echo
    echo "Next:"
    echo "    myDockersBuild $PROJECT"
    echo "    cd $ROOT && docker compose up -d"

    echo "To INIT DBs:"
    echo "    cd $ROOT && docker compose up -d"
    echo "    cd $ROOT && docker compose up -d && myDockersInitDBs $PROJECT"

    if [ -d "$TPL/postgres" ]; then
        echo "Adminer login (password: $PROJECT):"
        echo "    http://localhost:$PMA_PORT/?pgsql=pgdb&username=$PROJECT&db=$PROJECT"
    fi

}
