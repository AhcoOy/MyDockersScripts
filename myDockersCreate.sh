
# Resolve the directory this script lives in (works when sourced from bash or zsh)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersScriptPath="${BASH_SOURCE[0]}"
else
    _myDockersScriptPath="${(%):-%x}"
fi
MYDOCKERS_TEMPLATE_DIR="$(cd "$(dirname "$_myDockersScriptPath")" && pwd)/templates"
unset _myDockersScriptPath


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
        cp "$MYDOCKERS_TEMPLATE_DIR/gitignore" "$root/.gitignore"
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


### create new Docker LAMP project
myDockersCreate() {

    if [ $# -lt 5 ] || [ $# -gt 6 ]; then
        echo "Usage:"
        echo "    myDockersCreate <Project> <SubProject> <HTTP_PORT> <MYSQL_PORT> <PHPMYADMIN_PORT> [PHP_IMAGE]"
        echo
        echo "Example:"
        echo "    myDockersCreate moduledev prestashop91 8890 8906 8902 php:8.5-apache"
        echo "    myDockersCreate myapp mysubproject 8080 3306 8081"
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
    local ROOT="$HOME/MyDockers/$PROJECT"
    local TPL="$MYDOCKERS_TEMPLATE_DIR"
    local WEB_DIR="${PHP_ID}_${SUB_PROJECT}_web"
    local SRC_DIR="${PHP_ID}_${SUB_PROJECT}_src"

    if [ ! -d "$TPL" ]; then
        echo "Templates folder not found:"
        echo "    $TPL"
        return 1
    fi

    if [ -d "$ROOT" ]; then
        echo "Project already exists:"
        echo "    $ROOT"
        return 1
    fi

    echo "Creating $ROOT"

    # docker exec -it -u myproject myproject_web bash

    mkdir -p "$ROOT"/{apache,mariadb/init,data/mysql,home/$PROJECT,$WEB_DIR,$SRC_DIR}

    renderTemplate "$TPL/docker-compose.yml"  > "$ROOT/docker-compose.yml"
    renderTemplate "$TPL/web-service.yml"    >> "$ROOT/docker-compose.yml"
    renderTemplate "$TPL/php/Dockerfile"      > "$ROOT/$WEB_DIR/Dockerfile"
    renderTemplate "$TPL/mariadb/Dockerfile"  > "$ROOT/mariadb/Dockerfile"
    renderTemplate "$TPL/mariadb/my.cnf"      > "$ROOT/mariadb/my.cnf"
    renderTemplate "$TPL/mariadb/init.sql"    > "$ROOT/mariadb/init/init-${PHP_ID}_${SUB_PROJECT}.sql"
    renderTemplate "$TPL/mariadb/initDb.sh"   > "$ROOT/mariadb/initDb.sh"
    renderTemplate "$TPL/apache/vhost.conf"   > "$ROOT/apache/vhost.conf"

    chmod +x "$ROOT/mariadb/initDb.sh"

    touch "$ROOT/$SRC_DIR/index.php"

    myDockersCommit "$ROOT" "myDockersCreate $PROJECT $SUB_PROJECT ($PHP_IMAGE)"

    echo
    echo "Done."
    echo
    echo "Next:"
    echo "    cd $ROOT && docker compose up -d --build"
    echo "To INIT DBs:"
    echo "    cd $ROOT && mariadb/initDb.sh"
    echo "    cd $ROOT && docker compose up -d --build && mariadb/initDb.sh"

}
