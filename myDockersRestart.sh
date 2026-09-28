
# Load shared helpers (_myDockersDaemonCheck)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersRestartSource="${BASH_SOURCE[0]}"
else
    _myDockersRestartSource="${(%):-%x}"
fi

source "$(cd "$(dirname "$_myDockersRestartSource")" && pwd)/myDockersCreate.sh"
unset _myDockersRestartSource


### 'docker compose down' + 'up -d' every project under ~/MyDockers that is
### currently running; stopped projects are left alone
myDockersRestart() {

    if [ $# -ne 0 ]; then
        echo "Usage:"
        echo "    myDockersRestart"
        echo
        echo "Restarts (down + up -d) every running compose project under $HOME/MyDockers."
        return 1
    fi

    local BASE="$HOME/MyDockers"

    _myDockersDaemonCheck || return 1

    # 'docker compose ls' lists projects with running containers:
    #   NAME  STATUS  CONFIG FILES   (status may contain a space, files are last)
    # capture the config files now — once down, compose forgets them
    local entries
    entries="$(docker compose ls 2>/dev/null | awk 'NR > 1 { print $1 "|" $NF }' \
        | grep "|$BASE/")"

    if [ -z "$entries" ]; then
        echo "No running projects under:"
        echo "    $BASE"
        return 0
    fi

    local entry name files first label failed="" restarted=0

    echo "Restarting running MyDockers projects in $BASE"
    echo

    for entry in $(echo "$entries"); do
        name="${entry%%|*}"
        files="${entry#*|}"
        first="${files%%,*}"
        label="$(dirname "${first#$BASE/}")"

        printf "%-40s" "  $label"
        if ! docker compose -p "$name" down >/dev/null 2>&1; then
            echo "FAILED (down)"
            failed="$failed $label"
            continue
        fi
        # COMPOSE_FILE takes a ':'-separated list; the project directory is
        # the first file's folder, same as when it was started
        if (cd "$(dirname "$first")" && \
            COMPOSE_FILE="$(echo "$files" | tr ',' ':')" \
            docker compose -p "$name" up -d >/dev/null 2>&1); then
            echo "RESTARTED"
            restarted=$((restarted + 1))
        else
            echo "FAILED (up)"
            failed="$failed $label"
        fi
    done

    echo
    if [ -n "$failed" ]; then
        echo "FAILED:$failed"
        echo "Check manually:"
        local p
        for p in $(echo "$failed"); do
            echo "    cd $BASE/$p && docker compose up -d"
        done
        return 1
    fi

    echo "$restarted project(s) restarted."
}
