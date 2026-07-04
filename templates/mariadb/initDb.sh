#!/bin/bash

set -e

PROJECT="__PROJECT__"
DB_CONTAINER="${PROJECT}_db"

for sql_file in ./mariadb/init/*.sql; do
    [ -e "$sql_file" ] || continue

    echo "Running $sql_file"

    docker exec -i "$DB_CONTAINER" \
        mariadb -uroot -p"root" \
        < "$sql_file"
done
