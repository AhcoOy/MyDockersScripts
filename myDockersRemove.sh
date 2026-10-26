
# Load shared helpers (_myDockersDaemonCheck)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersRemoveSource="${BASH_SOURCE[0]}"
else
    _myDockersRemoveSource="${(%):-%x}"
fi

source "$(cd "$(dirname "$_myDockersRemoveSource")" && pwd)/myDockersCreate.sh"
unset _myDockersRemoveSource


### remove a project for good: its containers, network, volumes and built
### images, then the whole ~/MyDockers/<Project> folder (src and data too)
myDockersRemove() {

    if [ $# -ne 1 ]; then
        echo "Usage:"
        echo "    myDockersRemove <Project>"
        echo
        echo "Stops the project, removes its containers, network, volumes and the"
        echo "images built for it, then deletes $HOME/MyDockers/<Project> entirely."
        echo "Pulled base images (phpmyadmin, adminer, php:*, ...) are kept."
        return 1
    fi

    local PROJECT="$1"
    local BASE="$HOME/MyDockers"
    local ROOT="$BASE/$PROJECT"

    case "$PROJECT" in
        ""|.|..|*/*)
            echo "Invalid project name: '$PROJECT'"
            return 1
            ;;
    esac

    if [ ! -d "$ROOT" ]; then
        echo "Project does not exist:"
        echo "    $ROOT"
        return 1
    fi

    # compose files: the project root, plus one level down for projects that
    # keep theirs in a subfolder (data/ and *_src/ never hold ours)
    local composes
    composes="$(find "$ROOT" -maxdepth 2 \
        \( -name data -o -name '*_src' -o -name '.git' \) -prune -o \
        -type f \( -name docker-compose.yml -o -name docker-compose.yaml \
                   -o -name compose.yml -o -name compose.yaml \) -print 2>/dev/null | sort)"

    if [ -z "$composes" ] && [ ! -f "$ROOT/.myDockersTemplate" ]; then
        echo "Not a MyDockers project (no compose file found):"
        echo "    $ROOT"
        echo "Delete it by hand if you really want it gone."
        return 1
    fi

    _myDockersDaemonCheck || return 1

    # images compose built for this project: <project>-<service>, where the
    # compose project name is the folder name lowercased, invalid chars dropped
    local cname images
    cname="$(printf '%s' "$PROJECT" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_-')"
    images="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -E "^${cname}-(db|pgdb|php[a-z0-9]*-.+-web):" | sort)"

    local compose dir
    echo "This will PERMANENTLY remove project '$PROJECT':"
    echo
    for compose in $(echo "$composes"); do
        dir="$(dirname "$compose")"
        echo "  containers, network and volumes of ${compose#$BASE/}"
        (cd "$dir" && docker compose ps -a --format '{{.Name}}' 2>/dev/null) | sed 's/^/      /'
    done
    if [ -n "$images" ]; then
        echo "  images:"
        echo "$images" | sed 's/^/      /'
    fi
    echo "  folder (including *_src code and data/ databases):"
    echo "      $ROOT  ($(du -sh "$ROOT" 2>/dev/null | cut -f1))"
    echo
    printf "Type the project name to confirm: "
    local answer
    read -r answer
    if [ "$answer" != "$PROJECT" ]; then
        echo "Cancelled, nothing removed."
        return 1
    fi
    echo

    # host-database projects (LAlMP): their databases and users live in this
    # machine's shared MariaDB, outside the project — rebuilt as DROPs from
    # the CREATEs in hostdb/init/, and only dropped on an explicit yes
    local hostsql="" drop_hostdb=""
    if [ -d "$ROOT/hostdb/init" ]; then
        hostsql="$(find "$ROOT/hostdb/init" -maxdepth 1 -name '*.sql' -exec cat {} + 2>/dev/null \
            | sed -nE -e "s/^CREATE DATABASE IF NOT EXISTS (\`[^\`]+\`).*/DROP DATABASE IF EXISTS \1;/p" \
                      -e "s/^CREATE USER IF NOT EXISTS ('[^']+'@'[^']+').*/DROP USER IF EXISTS \1;/p" \
            | awk '!seen[$0]++')"
    fi
    if [ -n "$hostsql" ]; then
        echo "Its databases and users on this machine's MariaDB:"
        echo "$hostsql" | sed 's/^/      /'
        printf "Drop them too? [y/N] "
        read -r answer
        case "$answer" in
            y|Y|yes|YES) drop_hostdb=1 ;;
            *) echo "Keeping them." ;;
        esac
        echo
    fi

    # 1. containers, network, volumes and the images of current services
    for compose in $(echo "$composes"); do
        dir="$(dirname "$compose")"
        printf "%-50s" "  down ${compose#$BASE/}"
        if (cd "$dir" && docker compose -f "$compose" down --volumes --remove-orphans --rmi local >/dev/null 2>&1); then
            echo "OK"
        else
            echo "FAILED"
            echo
            echo "Folder NOT deleted. Check manually:"
            echo "    cd $dir && docker compose down --volumes --remove-orphans --rmi local"
            return 1
        fi
    done

    # 2. leftover images, e.g. of services that were dropped from the compose
    local img output
    for img in $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
                 | grep -E "^${cname}-(db|pgdb|php[a-z0-9]*-.+-web):"); do
        printf "%-50s" "  rmi $img"
        if docker rmi "$img" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAILED (in use?)"
        fi
    done

    # 3. host databases and users, when asked to (the folder still holds the
    #    init files, so a failure here can simply be retried by hand)
    if [ -n "$drop_hostdb" ]; then
        if _myDockersHostDbLogin; then
            printf "%-50s" "  drop host databases and users"
            if output=$(echo "$hostsql" | _myDockersHostDb 2>&1); then
                echo "OK"
            else
                echo "FAILED"
                echo "$output" | sed 's/^/      /'
                drop_hostdb=""
            fi
            _myDockersHostDbLogout
        else
            drop_hostdb=""
        fi
        if [ -z "$drop_hostdb" ]; then
            echo "  Host databases NOT dropped — run as the MariaDB admin:"
            echo "$hostsql" | sed 's/^/      /'
        fi
    fi

    # 4. the folder; database dirs in data/ are often mode 700, and on a
    #    native Linux engine owned by container uids (999) — so retry after
    #    chmod, then from inside a container (root there can delete them)
    case "$PWD/" in "$ROOT"/*) cd "$BASE" ;; esac
    printf "%-50s" "  delete folder ~/MyDockers/$PROJECT"
    rm -rf "$ROOT" 2>/dev/null
    if [ -e "$ROOT" ]; then
        chmod -R u+rwX "$ROOT" 2>/dev/null
        rm -rf "$ROOT" 2>/dev/null
    fi
    if [ -e "$ROOT" ]; then
        docker run --rm -v "$BASE":/mydockers alpine \
            sh -c "chmod -R u+rwX '/mydockers/$PROJECT'; rm -rf '/mydockers/$PROJECT'" >/dev/null 2>&1
    fi
    if [ -e "$ROOT" ]; then
        echo "FAILED"
        echo
        echo "Delete the rest by hand:"
        echo "    sudo rm -rf \"$ROOT\""
        return 1
    fi
    echo "OK"

    echo
    echo "Project '$PROJECT' removed."
}
