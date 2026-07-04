#!/bin/bash

set -e

PROJECT="__PROJECT__"
DB_CONTAINER="${PROJECT}_postgres_db"

# wait until the server accepts connections stably (on first boot the
# entrypoint runs a temporary server, then restarts into the real one)
echo "Waiting for $DB_CONTAINER"
for i in $(seq 1 30); do
    if docker exec "$DB_CONTAINER" psql -U "$PROJECT" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        sleep 2
        docker exec "$DB_CONTAINER" psql -U "$PROJECT" -d postgres -c "SELECT 1;" >/dev/null 2>&1 && break
    fi
    sleep 1
done

for sql_file in ./postgres/init/*.sql; do
    [ -e "$sql_file" ] || continue

    echo "Running $sql_file"

    docker exec -i "$DB_CONTAINER" \
        psql -U "$PROJECT" -d postgres -v ON_ERROR_STOP=1 \
        < "$sql_file"
done
