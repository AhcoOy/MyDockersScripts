
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

    _myDockersDaemonCheck || return 1

    # Pre-validate the FROM image of every php Dockerfile — a malformed
    # image name (php7.0:apache instead of php:7.0-apache) from an older
    # myDockersAdd cannot be pulled and has corrupted the compose file;
    # catch it here instead of wasting a build run.
    local df from bad_df=""
    for df in $(find "$ROOT" -maxdepth 2 -name Dockerfile 2>/dev/null); do
        from=$(awk 'toupper($1) == "FROM" { print $2; exit }' "$df")
        case "$from" in
            php*)
                if ! _myDockersCheckPhpImage "$from" >/dev/null 2>&1; then
                    bad_df=1
                    echo "Invalid php image in:"
                    echo "    $df"
                    echo
                    _myDockersCheckPhpImage "$from"
                fi
                ;;
        esac
    done

    if [ -n "$bad_df" ]; then
        echo
        echo "Fix the FROM line by hand, or undo the myDockersAdd that created it:"
        echo "    git -C $ROOT log --oneline -5"
        echo "    git -C $ROOT reset --hard HEAD~1   # if the bad add is the last commit"
        echo "then delete its leftover folders and re-add with a valid image:"
        echo "    myDockersAdd $PROJECT <SubProject> php:8.4-apache"
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
        echo
        echo "docker compose says:"
        (cd "$ROOT" && docker compose config --services 2>&1 >/dev/null) | sed 's/^/    /'
        echo
        echo "The compose file is invalid — this is NOT caused by running"
        echo "containers (reading works fine while the stack is up). Typical"
        echo "cause: a mistyped PHP_IMAGE in an earlier myDockersCreate/"
        echo "myDockersAdd (must look like php:8.4-apache). Inspect, then fix"
        echo "the file by hand or undo the bad change:"
        echo "    cd $ROOT && docker compose config"
        echo "    git -C $ROOT log --oneline -5"
        echo "    git -C $ROOT reset --hard HEAD~1   # if it is the last commit"
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

    if [ -z "$failed" ]; then
        echo
        echo "Next:"
        echo "    cd $ROOT && docker compose up -d  &&  myDockersInitDBs $PROJECT"
    fi

    [ -z "$failed" ]
}
