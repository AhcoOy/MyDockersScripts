myDockersHints() {

    if [ $# -gt 2 ]; then
        echo "Usage:"
        echo "    myDockersHints                          # list all projects"
        echo "    myDockersHints <Project> [SubProject]   # hints for one project"
        echo
        echo "Example:"
        echo "    myDockersHints myshop"
        echo "    myDockersHints myshop ps91"
        return 1
    fi

    ############################################################
    # no arguments: scan $HOME/MyDockers, output real examples
    ############################################################
    if [ $# -eq 0 ]; then
        local BASE="$HOME/MyDockers"
        local running
        running=$(docker ps --format '{{.Names}}' 2>/dev/null)

        echo
        echo "========================================================"
        echo "MyDockers projects in $BASE"
        echo "========================================================"

        local compose proj webs web sub state found=""

        for compose in "$BASE"/*/docker-compose.yml; do
            [ -e "$compose" ] || continue
            found=1
            proj=$(basename "$(dirname "$compose")")

            echo
            echo "$proj"

            webs=$(grep -o 'container_name: .*_web$' "$compose" | awk '{print $2}')

            if [ -z "$webs" ]; then
                echo "    (no web containers in docker-compose.yml)"
                echo "    myDockersHints $proj"
                continue
            fi

            for web in $(echo "$webs"); do
                state=""
                echo "$running" | grep -qx "$web" && state="   (running)"
                case "$web" in
                    ${proj}_*_web)
                        sub="${web#${proj}_}"
                        sub="${sub%_web}"
                        echo "    myDockersHints $proj $sub$state"
                        ;;
                    *)
                        echo "    $web$state"
                        ;;
                esac
            done
        done

        if [ -z "$found" ]; then
            echo
            echo "No projects found. Create one:"
            echo "    myDockersCreate <Project> <SubProject> <HTTP_PORT> <MYSQL_PORT> <PMA_PORT> [PHP_IMAGE]"
        fi

        echo
        echo "========================================================"
        echo
        return 0
    fi

    local P="$1"
    local SUB="${2:-}"
    local COMPOSE="$HOME/MyDockers/$P/docker-compose.yml"

    if [ ! -f "$COMPOSE" ]; then
        echo "ERROR: no such project: $P"
        echo "    ($COMPOSE not found)"
        echo
        echo "List all projects with:"
        echo "    myDockersHints"
        return 1
    fi

    # all web containers of the project, from its docker-compose.yml
    local WEBS
    WEBS=$(grep -o 'container_name: .*_web$' "$COMPOSE" | awk '{print $2}')

    # web container the hints point at: <Project>_<SubProject>_web,
    # or the project's first web container
    local WEB=""
    if [ -n "$SUB" ]; then
        WEB="${P}_${SUB}_web"

        if ! echo "$WEBS" | grep -qx "$WEB"; then
            echo "ERROR: no container $WEB in project $P"
            echo
            echo "Available web containers:"
            local w s
            for w in $(echo "$WEBS"); do
                case "$w" in
                    ${P}_*_web)
                        s="${w#${P}_}"
                        s="${s%_web}"
                        echo "    myDockersHints $P $s"
                        ;;
                    *)
                        echo "    $w"
                        ;;
                esac
            done
            return 1
        fi
    else
        WEB=$(echo "$WEBS" | head -1)
        WEB="${WEB:-${P}_<SubProject>_web}"
    fi

    cat <<EOF

========================================================
Docker hints for project: $P   (web container: $WEB)
========================================================

# Web containers in this project (myDockersHints $P <SubProject>):
$(echo "${WEBS:-(no web containers found)}" | sed 's/^/    /')

# Start
cd ~/MyDockers/$P && docker compose up -d

# Stop
cd ~/MyDockers/$P && docker compose down

# Restart
cd ~/MyDockers/$P && docker compose restart

# Rebuild (with build logs and summary)
myDockersBuild $P

# Rebuild without cache
cd ~/MyDockers/$P && docker compose build --no-cache
cd ~/MyDockers/$P && docker compose up -d

# Create / verify the databases
myDockersInitDBs $P

# Add another subproject
myDockersAdd $P <SubProject> [PHP_IMAGE]

--------------------------------------------------------
Shell
--------------------------------------------------------

# Root shell
docker exec -it $WEB bash

# Project user shell
docker exec -it -u ${P} $WEB bash

# MariaDB
docker exec -it ${P}_db mariadb -uroot -proot

--------------------------------------------------------
Logs
--------------------------------------------------------

# Apache / PHP
docker logs -f $WEB

# MariaDB
docker logs -f ${P}_db

# phpMyAdmin
docker logs -f ${P}_phpmyadmin

# All services
cd ~/MyDockers/$P && docker compose logs -f

--------------------------------------------------------
Apache
--------------------------------------------------------

# Error log
docker exec -it $WEB tail -f /var/log/apache2/error.log

# Access log
docker exec -it $WEB tail -f /var/log/apache2/access.log

--------------------------------------------------------
PHP
--------------------------------------------------------

# Version
docker exec -it $WEB php -v

# Loaded modules
docker exec -it $WEB php -m

# php.ini
docker exec -it $WEB php --ini

--------------------------------------------------------
MariaDB
--------------------------------------------------------

# Variables
docker exec -it ${P}_db mariadb -uroot -proot -e "SHOW VARIABLES;"

# File per table
docker exec -it ${P}_db mariadb -uroot -proot \\
-e "SHOW VARIABLES LIKE 'innodb_file_per_table';"

--------------------------------------------------------
Container info
--------------------------------------------------------

docker ps
docker images
docker system df

========================================================

EOF
}
