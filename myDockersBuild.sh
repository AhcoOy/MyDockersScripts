
# Load shared helpers (myDockersCommit, myDockersInitDBs, MYDOCKERS_TEMPLATE_DIR)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersBuildSource="${BASH_SOURCE[0]}"
else
    _myDockersBuildSource="${(%):-%x}"
fi
_myDockersBuildDir="$(cd "$(dirname "$_myDockersBuildSource")" && pwd)"
source "$_myDockersBuildDir/myDockersCreate.sh"
source "$_myDockersBuildDir/myDockersInitDBs.sh"
unset _myDockersBuildSource _myDockersBuildDir


### build all services of a Docker LAMP project, one log per service
myDockersBuild() {

    if [ $# -ne 1 ]; then
        echo "Usage:"
        echo "    myDockersBuild <Project>"
        echo
        echo "Example:"
        echo "    myDockersBuild ahco_ps"
        return 1
    fi

    local PROJECT="$1"
    local ROOT="$HOME/MyDockers/$PROJECT"
    local COMPOSE="$ROOT/docker-compose.yml"
    local LOG_DIR="$ROOT/build_logs"

    if [ ! -d "$ROOT" ]; then
        echo "Project does not exist:"
        echo "    $ROOT"
        return 1
    fi

    if [ ! -f "$COMPOSE" ]; then
        echo "docker-compose.yml not found:"
        echo "    $COMPOSE"
        return 1
    fi

    mkdir -p "$LOG_DIR"

    local RUN_ID
    RUN_ID=$(date +%Y-%m-%d_%H%M%S)
    local SUMMARY="$LOG_DIR/${RUN_ID}_summary.log"

    local services
    services=$(cd "$ROOT" && docker compose config --services 2>/dev/null)

    if [ -z "$services" ]; then
        echo "Could not read services from:"
        echo "    $COMPOSE"
        return 1
    fi

    echo "Building project $PROJECT"
    echo "Logs: $LOG_DIR"
    echo

    echo "Build summary for $PROJECT ($RUN_ID)" > "$SUMMARY"
    echo "======================================" >> "$SUMMARY"

    local service log warnings failed=""

    for service in $(echo "$services"); do
        log="$LOG_DIR/${RUN_ID}_${service}.log"
        printf "%-40s" "  $service"

        if ( cd "$ROOT" && docker compose build --progress=plain "$service" ) > "$log" 2>&1; then
            # fail-soft warnings from the Dockerfile template
            warnings=$(grep -E '^#[0-9]+ [0-9.]+ WARNING' "$log" | sed -E 's/^#[0-9]+ [0-9.]+ //' | sort -u)

            if [ -n "$warnings" ]; then
                echo "OK (with warnings)"
                echo "$service: OK (with warnings)" >> "$SUMMARY"
                echo "$warnings" | sed 's/^/    /' >> "$SUMMARY"
            else
                echo "OK"
                echo "$service: OK" >> "$SUMMARY"
            fi
        else
            echo "FAILED"
            failed="$failed $service"
            echo "$service: FAILED (see ${RUN_ID}_${service}.log)" >> "$SUMMARY"
            tail -5 "$log" | sed 's/^/    /' >> "$SUMMARY"
        fi
    done

    echo "======================================" >> "$SUMMARY"

    echo
    local result="all services OK"
    if [ -n "$failed" ]; then
        result="FAILED:$failed"
        echo "FAILED:$failed" | tee -a "$SUMMARY"
        echo "Logs:"
        echo "    $LOG_DIR"
        echo "Summary:"
        echo "    $SUMMARY"
    else
        echo "All services built." | tee -a "$SUMMARY"
        echo "Summary:"
        echo "    $SUMMARY"
    fi

    myDockersInitDBs "$PROJECT"

    myDockersCommit "$ROOT" "myDockersBuild $PROJECT ($result)"

    [ -z "$failed" ]
}
