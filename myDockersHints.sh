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
            echo "    myDockersCreate <Project> <SubProject> <HTTP_PORT> <MYSQL_PORT> <PMA_PORT> [PHP_IMAGE] [TEMPLATES]"
        fi

        echo
        echo "========================================================"
        echo
        return 0
    fi

    ############################################################
    # one project: hints for the containers it actually has
    ############################################################
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

    # which db / admin containers does this project actually have?
    local HAS_MARIADB="" HAS_POSTGRES="" HAS_PMA="" HAS_ADMINER=""
    grep -q "container_name: ${P}_db\$" "$COMPOSE"          && HAS_MARIADB=1
    grep -q "container_name: ${P}_postgres_db\$" "$COMPOSE" && HAS_POSTGRES=1
    grep -q "container_name: ${P}_phpmyadmin\$" "$COMPOSE"  && HAS_PMA=1
    grep -q "container_name: ${P}_adminer\$" "$COMPOSE"     && HAS_ADMINER=1

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
myDockersAdd $P <SubProject> [PHP_IMAGE] [TEMPLATE]

--------------------------------------------------------
Shell
--------------------------------------------------------

# Root shell
docker exec -it $WEB bash

# Project user shell
docker exec -it -u ${P} $WEB bash
EOF

    [ -n "$HAS_MARIADB" ] && cat <<EOF

# MariaDB
docker exec -it ${P}_db mariadb -uroot -proot
EOF

    [ -n "$HAS_POSTGRES" ] && cat <<EOF

# PostgreSQL "root" shell — the superuser is ${P} (password: ${P})
docker exec -it ${P}_postgres_db psql -U ${P} -d ${P}
EOF

    cat <<EOF

--------------------------------------------------------
Logs
--------------------------------------------------------

# Apache / PHP
docker logs -f $WEB
EOF

    [ -n "$HAS_MARIADB" ] && cat <<EOF

# MariaDB
docker logs -f ${P}_db
EOF

    [ -n "$HAS_POSTGRES" ] && cat <<EOF

# PostgreSQL
docker logs -f ${P}_postgres_db
EOF

    [ -n "$HAS_PMA" ] && cat <<EOF

# phpMyAdmin
docker logs -f ${P}_phpmyadmin
EOF

    [ -n "$HAS_ADMINER" ] && cat <<EOF

# Adminer
docker logs -f ${P}_adminer
EOF

    cat <<EOF

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
EOF

    [ -n "$HAS_MARIADB" ] && cat <<EOF

--------------------------------------------------------
MariaDB
--------------------------------------------------------

# Variables
docker exec -it ${P}_db mariadb -uroot -proot -e "SHOW VARIABLES;"

# File per table
docker exec -it ${P}_db mariadb -uroot -proot \\
-e "SHOW VARIABLES LIKE 'innodb_file_per_table';"
EOF

    if [ -n "$HAS_POSTGRES" ]; then
        local ADMINER_PORT PG_PORT
        ADMINER_PORT=$(grep -o '"[0-9]*:8080"' "$COMPOSE" | cut -d'"' -f2 | cut -d: -f1)
        PG_PORT=$(grep -o '"[0-9]*:5432"' "$COMPOSE" | cut -d'"' -f2 | cut -d: -f1)

        cat <<EOF

--------------------------------------------------------
PostgreSQL
--------------------------------------------------------

# "root" login — the superuser is ${P}, password: ${P}
docker exec -it ${P}_postgres_db psql -U ${P} -d ${P}
EOF

        [ -n "$PG_PORT" ] && cat <<EOF

# "root" login from the host (asks the password: ${P})
psql -h localhost -p ${PG_PORT} -U ${P} -d ${P}
EOF

        cat <<EOF

# List databases
docker exec -it ${P}_postgres_db psql -U ${P} -d postgres -c "\\l"

# Settings
docker exec -it ${P}_postgres_db psql -U ${P} -d postgres -c "SHOW ALL;"
EOF

        [ -n "$ADMINER_PORT" ] && cat <<EOF

# Adminer login (password: ${P})
http://localhost:${ADMINER_PORT}/?pgsql=pgdb&username=${P}&db=${P}
EOF
    fi

    cat <<EOF

--------------------------------------------------------
Container info
--------------------------------------------------------

docker ps
docker images
docker system df

========================================================

EOF
}
