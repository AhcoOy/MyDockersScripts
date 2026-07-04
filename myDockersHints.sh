myDockersHints() {

    if [ $# -ne 1 ]; then
        echo "Usage:"
        echo "    myDockersHints <project>"
        return 1
    fi

    local P="$1"

    cat <<EOF

========================================================
Docker hints for project: $P
========================================================

# Start
cd ~/MyDockers/$P && docker compose up -d

# Stop
cd ~/MyDockers/$P && docker compose down

# Restart
cd ~/MyDockers/$P && docker compose restart

# Rebuild
docker compose down
cd ~/MyDockers/$P && docker compose up -d --build

# Rebuild without cache
cd ~/MyDockers/$P && docker compose build --no-cache
cd ~/MyDockers/$P && docker compose up -d

--------------------------------------------------------
Shell
--------------------------------------------------------

# Root shell
docker exec -it ${P}_web bash

# Project user shell
docker exec -it -u ${P} ${P}_web bash

# MariaDB
docker exec -it ${P}_db mariadb -uroot -proot

--------------------------------------------------------
Logs
--------------------------------------------------------

# Apache / PHP
docker logs -f ${P}_web

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
docker exec -it ${P}_web tail -f /var/log/apache2/error.log

# Access log
docker exec -it ${P}_web tail -f /var/log/apache2/access.log

--------------------------------------------------------
PHP
--------------------------------------------------------

# Version
docker exec -it ${P}_web php -v

# Loaded modules
docker exec -it ${P}_web php -m

# php.ini
docker exec -it ${P}_web php --ini

--------------------------------------------------------
MariaDB
--------------------------------------------------------

# Variables
docker exec -it ${P}_db mariadb -uroot -proot -e "SHOW VARIABLES;"

# File per table
docker exec -it ${P}_db mariadb -uroot -proot \
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
