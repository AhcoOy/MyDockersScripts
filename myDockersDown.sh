
# Load shared helpers (_myDockersDaemonCheck)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersDownSource="${BASH_SOURCE[0]}"
else
    _myDockersDownSource="${(%):-%x}"
fi

source "$(cd "$(dirname "$_myDockersDownSource")" && pwd)/myDockersCreate.sh"
unset _myDockersDownSource


### run 'docker compose down' in every project under ~/MyDockers —
### handy before shutting down or rebooting the host
myDockersDown() {

    if [ $# -ne 0 ]; then
        echo "Usage:"
        echo "    myDockersDown"
        echo
        echo "Runs 'docker compose down' in every project under $HOME/MyDockers."
        return 1
    fi

    local BASE="$HOME/MyDockers"

    _myDockersDaemonCheck || return 1

    local compose dir proj found="" failed="" stopped=0 idle=0

    echo "Stopping MyDockers projects in $BASE"
    echo

    for compose in $(find "$BASE" -maxdepth 2 -name docker-compose.yml 2>/dev/null | sort); do
        found=1
        dir="$(dirname "$compose")"
        proj="$(basename "$dir")"

        # skip projects that have no containers at all
        if [ -z "$(cd "$dir" && docker compose ps -aq 2>/dev/null)" ]; then
            printf "%-40salready down\n" "  $proj"
            idle=$((idle + 1))
            continue
        fi

        printf "%-40s" "  $proj"
        if (cd "$dir" && docker compose down >/dev/null 2>&1); then
            echo "DOWN"
            stopped=$((stopped + 1))
        else
            echo "FAILED"
            failed="$failed $proj"
        fi
    done

    if [ -z "$found" ]; then
        echo "No projects found in:"
        echo "    $BASE"
        return 1
    fi

    echo
    if [ -n "$failed" ]; then
        echo "FAILED:$failed"
        echo "Check manually:"
        local p
        for p in $(echo "$failed"); do
            echo "    cd $BASE/$p && docker compose down"
        done
        return 1
    fi

    echo "$stopped project(s) stopped, $idle already down. Safe to reboot."
}
