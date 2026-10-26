
# Resolve the directory this script lives in (works when sourced from bash or zsh)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersScriptPath="${BASH_SOURCE[0]}"
else
    _myDockersScriptPath="${(%):-%x}"
fi
MYDOCKERS_TEMPLATE_DIR="$(cd "$(dirname "$_myDockersScriptPath")" && pwd)/templates"
# myDockersCreate runs myDockersInitDBs for host-database (LAlMP) projects
source "$(dirname "$MYDOCKERS_TEMPLATE_DIR")/myDockersInitDBs.sh"
unset _myDockesrScriptPath


# Re-source every myDockers script — run after editing them, so the
# functions in your open shell match the code on disk.
myDockersReload() {
    local dir f
    dir="$(dirname "$MYDOCKERS_TEMPLATE_DIR")"
    for f in "$dir"/*.sh; do
        [ -f "$f" ] && source "$f"
    done
    echo "myDockers commands reloaded from $dir"
}


# Check that the docker daemon is up and answering. A wedged daemon can
_myDockersDaemonCheck() {
    command -v docker >/dev/null 2>&1 || {
        echo "ERROR: docker command not found."
        return 1
    }

    docker info >/dev/null 2>&1 || {
        echo "ERROR: the docker daemon is not answering."
        echo
        echo "Restart Docker Desktop (whale menu > Restart), or from the terminal:"
        echo "    osascript -e 'quit app \"Docker Desktop\"' && open -a Docker"
        echo "Then wait until this works again:"
        echo "    docker info"
        return 1
    }
    return 0
}


# Pick the next free 172.30.N.0/24 subnet, scanning every project's
# docker-compose.yml under ~/MyDockers for subnets already taken.
_myDockersNextSubnet() {
    local used n=1
    used=$(find "$HOME/MyDockers" -maxdepth 2 -name docker-compose.yml -exec \
            grep -hoE 'subnet: *172\.30\.[0-9]+\.0/24' {} + 2>/dev/null \
        | grep -oE '172\.30\.[0-9]+' | cut -d. -f3 | sort -un)

    while printf '%s\n' "$used" | grep -qx "$n"; do
        n=$((n + 1))
    done

    if [ "$n" -gt 254 ]; then
        echo "ERROR: no free 172.30.N.0/24 subnet left under $HOME/MyDockers" >&2
        return 1
    fi

    echo "172.30.$n"
}


# Host ports in use, one per line: every port published by a compose file
# under ~/MyDockers (also project subfolders and *_src), plus every TCP
# port something on this machine listens on (ss on Linux, lsof on macOS).
_myDockersUsedPorts() {
    {
        find "$HOME/MyDockers" -maxdepth 3 -type f \
            \( -name docker-compose.yml -o -name docker-compose.yaml \
               -o -name compose.yml -o -name compose.yaml \) \
            -exec cat {} + 2>/dev/null \
        | sed -nE 's/^[[:space:]]*-[[:space:]]*"?([0-9.]+:)?([0-9]+):[0-9]+(\/(tcp|udp))?"?[[:space:]]*$/\2/p'

        if command -v ss >/dev/null 2>&1; then
            ss -Htln 2>/dev/null | awk '{ print $4 }' | sed 's/.*://'
        elif command -v lsof >/dev/null 2>&1; then
            lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $9 }' | sed 's/.*://'
        fi
    } | grep -E '^[0-9]+$' | sort -un
}

# Print which of the given ports are already in use (space-separated)
_myDockersPortsTaken() {
    local used p taken=""
    used=$(_myDockersUsedPorts)
    for p in "$@"; do
        printf '%s\n' "$used" | grep -qx "$p" && taken="$taken $p"
    done
    printf '%s' "${taken# }"
}

# First free 10-port segment (8100-8109, 8110-8119, ...): none of its ports
# published by a MyDockers project or listened on by anything on this
# machine. Start with MYDOCKERS_PORT_START (default 8100).
_myDockersFreePortSegment() {
    local used base="${MYDOCKERS_PORT_START:-8100}"
    used=$(_myDockersUsedPorts)

    while [ "$base" -le 65526 ]; do
        if ! printf '%s\n' "$used" | awk -v b="$base" '$1 >= b && $1 <= b + 9 { f = 1 } END { exit !f }'; then
            echo "$base"
            return 0
        fi
        base=$((base + 10))
    done

    echo "ERROR: no free 10-port segment from ${MYDOCKERS_PORT_START:-8100} up" >&2
    return 1
}


# Regenerate <project>/mounted_shared_etc/hosts from the hostname /
# ipv4_address pairs in docker-compose.yml. The file is mounted as
# /etc/hosts into every service, so all containers resolve each other
# by hostname (ssh ps91, curl http://ps8_last/, ...). Everything above
# the marker line is rewritten; custom entries below it are kept.
_myDockersWriteHosts() {
    local root="$1"
    local hosts="$root/mounted_shared_etc/hosts"
    local project
    project=$(basename "$root")
    local marker='###---- Add your custom host entries after this comment line, everything above will be regenerated, custom host entries kept ---- ###'

    mkdir -p "$root/mounted_shared_etc"

    # keep whatever was added by hand below the marker line
    local custom=""
    if [ -f "$hosts" ]; then
        custom=$(awk -v m="$marker" 'found { print } $0 == m { found = 1 }' "$hosts")
    fi

    # host-database projects (LAlMP): 'db' is this machine's MariaDB, reached
    # through Docker's host gateway; keep the previous address if the probe
    # cannot run (daemon down, no alpine image and no network)
    local hostdb_ip=""
    if [ -d "$root/hostdb" ]; then
        hostdb_ip=$(_myDockersHostGateway) \
            || hostdb_ip=$(awk -v m="$marker" '$0 == m { exit }
                                $2 == "db" && $1 ~ /^[0-9.]+$/ { print $1 }' "$hosts" 2>/dev/null | tail -1)
        if [ -z "$hostdb_ip" ]; then
            hostdb_ip="172.17.0.1"
            echo "WARNING: could not probe Docker's host gateway, 'db' set to $hostdb_ip"
            echo "         (rerun myDockersAdd/myDockersEmulate once docker answers to fix it)"
        fi
    fi

    {
        echo "# $project — hosts file, generated by myDockersCreate/myDockersAdd."
        echo "#"
        echo "# Mounted as /etc/hosts into EVERY service of this project, so all"
        echo "# containers resolve each other by hostname. Everything above the"
        echo "# marker line is rewritten each time a service is added; your own"
        echo "# entries below the marker line are kept."
        echo "#"
        echo "# Note: this file is bind-mounted — edit it in place (echo >> ...)."
        echo "# Editors that replace the file (vim, IDEs) break the mount for"
        echo "# running containers; after such an edit run: docker compose up -d"
        echo "127.0.0.1       localhost"
        echo "::1             localhost ip6-localhost ip6-loopback"
        if [ -n "$hostdb_ip" ]; then
            echo
            echo "# db — the HOST's MariaDB (no container), shared by all LAlMP projects,"
            echo "#      reached through Docker's host gateway"
            echo "#   from a container   : mariadb --skip-ssl -h db -u <DB_NAME> -p<DB_NAME> <DB_NAME>"
            echo "#                        (DB_NAME of each web service in docker-compose.yml)"
            echo "#   from this machine  : mariadb --skip-ssl -h 127.0.0.1 -u $project -p$project"
            printf '%-15s %s\n' "$hostdb_ip" "db"
        fi
        awk -v P="$project" '
            $1 == "container_name:" { cn = $2 }
            $1 == "hostname:"       { host = $2 }
            /^ *- "[0-9]+:[0-9]+"$/ && port == "" {
                p = $2; gsub(/"/, "", p); split(p, a, ":")
                port = a[1]; iport = a[2]
            }
            $1 == "ipv4_address:" && host != "" {
                printf "\n"
                if (host == "db") {
                    printf "# db — MariaDB, container %s\n", cn
                    printf "#   inside the network : mariadb --skip-ssl -h db -P 3306 -u %s -p%s\n", P, P
                    if (port != "")
                        printf "#   from this machine  : mariadb --skip-ssl -h 127.0.0.1 -P %s -u %s -p%s\n", port, P, P
                } else if (host == "pgdb") {
                    printf "# pgdb — PostgreSQL, container %s\n", cn
                    printf "#   inside the network : psql -h pgdb -U %s   (password %s)\n", P, P
                    if (port != "")
                        printf "#   from this machine  : psql -h 127.0.0.1 -p %s -U %s\n", port, P
                } else if (host == "phpmyadmin" || host == "adminer") {
                    url = (iport == "80") ? "http://" host "/" : "http://" host ":" iport "/"
                    printf "# %s — web UI, container %s\n", host, cn
                    printf "#   inside the network : curl %s\n", url
                    if (port != "")
                        printf "#   from this machine  : http://localhost:%s\n", port
                } else {
                    printf "# %s — Apache+PHP web service, container %s\n", host, cn
                    printf "#   ssh from another container : ssh %s@%s   (password: %s)\n", P, host, P
                    printf "#   web from another container : curl http://%s/\n", host
                    if (port != "")
                        printf "#   from this machine          : http://localhost:%s\n", port
                }
                printf "#   shell from this machine    : docker exec -it %s bash\n", cn
                printf "%-15s %s\n", $2, host
                cn = ""; host = ""; port = ""; iport = ""
            }' \
            "$root/docker-compose.yml"

        # Emulated HTTPS APIs (myDockersEmulate): any *:443 vhost in a
        # subproject's mounted_etc config redirects its ServerName domain
        # to that subproject's static IP, for every container.
        find "$root/mounted_etc" -mindepth 2 -maxdepth 2 -name vhost.conf 2>/dev/null \
        | while IFS= read -r vh; do
            sub=$(basename "$(dirname "$vh")")
            ip=$(awk -v h="$sub" '
                $1 == "hostname:" { found = ($2 == h) }
                found && $1 == "ipv4_address:" { print $2; exit }' \
                "$root/docker-compose.yml")
            [ -n "$ip" ] || continue
            awk '/<VirtualHost \*:443>/ { in443 = 1 }
                 /<\/VirtualHost>/      { in443 = 0 }
                 in443 && $1 == "ServerName" { print $2 }' "$vh" \
            | while IFS= read -r dom; do
                printf '\n# %s — HTTPS API emulated by %s\n' "$dom" "$sub"
                printf '#   from any container : curl https://%s/\n' "$dom"
                printf '%-15s %s\n' "$ip" "$dom"
            done
        done

        echo
        echo "$marker"
        if [ -n "$custom" ]; then printf '%s\n' "$custom"; fi
    } > "$hosts"
}


# Published host port of one container port, read from that service's
# block in <root>/docker-compose.yml (empty when not published)
_myDockersComposePort() {   # <root> <container name> <container port>
    awk -v c="$2" -v cp="$3" '
        $1 == "container_name:" { inblk = ($2 == c) }
        inblk && $0 ~ "\"[0-9]+:" cp "\"" {
            p = $2; gsub(/"/, "", p); split(p, a, ":"); print a[1]; exit
        }' "$1/docker-compose.yml"
}


# Append one subproject's credentials to <project>/credentials.txt, so a
# person (or a Claude session) opening the project finds every login in one
# place. Written at create, extended by myDockersAdd. A credentials.txt not
# written by these scripts (e.g. a symlink to your own notes) is left alone.
_myDockersWriteCredentials() {   # <root> <subproject> <db name> <http port>
    local root="$1" sub="$2" db="$3" http="$4"
    local file="$root/credentials.txt" project dbport adm
    local mark="# generated by myDockersCreate/myDockersAdd"
    project=$(basename "$root")

    if [ -e "$file" ] && ! grep -qxF "$mark" "$file" 2>/dev/null; then
        echo "NOTE: $file is not generated by myDockers — not touched."
        echo "      New subproject: database = user = password = $db"
        return 0
    fi

    if [ ! -e "$file" ]; then
        {
            echo "# $project — credentials (local development only)"
            echo "$mark"
            echo
            if [ -d "$root/hostdb" ]; then
                echo "Database server: this machine's localhost MariaDB (shared by all LAlMP projects)"
                echo "  from containers   : host db, port 3306"
                echo "  from this machine : mariadb --skip-ssl -h 127.0.0.1 -u <user> -p<password>"
                echo "Project user (all subproject databases, host phpMyAdmin): $project / $project"
            elif [ -d "$root/postgres" ]; then
                dbport=$(_myDockersComposePort "$root" "${project}_postgres_db" 5432)
                adm=$(_myDockersComposePort "$root" "${project}_adminer" 8080)
                echo "Database server: PostgreSQL container ${project}_postgres_db"
                echo "  from containers   : host pgdb, port 5432"
                [ -n "$dbport" ] && echo "  from this machine : 127.0.0.1:$dbport"
                echo "Superuser (project user, all databases): $project / $project"
                [ -n "$adm" ] && echo "Adminer: http://localhost:$adm/?pgsql=pgdb&username=$project&db=$project"
            elif [ -d "$root/mariadb" ]; then
                dbport=$(_myDockersComposePort "$root" "${project}_db" 3306)
                adm=$(_myDockersComposePort "$root" "${project}_phpmyadmin" 80)
                echo "Database server: MariaDB container ${project}_db"
                echo "  from containers   : host db, port 3306"
                [ -n "$dbport" ] && echo "  from this machine : 127.0.0.1:$dbport (mariadb --skip-ssl -h 127.0.0.1 -P $dbport ...)"
                echo "root / root; project user (all subproject databases): $project / $project"
                [ -n "$adm" ] && echo "phpMyAdmin: http://localhost:$adm"
            fi
            echo "SSH between containers: ssh $project@<subproject>, password $project"
        } > "$file"
    fi

    {
        echo
        echo "## $sub — container ${project}_${sub}_web${http:+, http://localhost:$http}"
        if [ -d "$root/hostdb" ]; then
            echo "Database (on this machine's localhost MariaDB): $db"
        else
            echo "Database: $db"
        fi
        echo "user = password = $db"
    } >> "$file"
}


# Make sure the project has its dev CA (mounted_shared_etc/ssl/ca.*) and
# the overlaid CA bundle (mounted_shared_etc/ca-certificates.crt = distro
# roots + dev CA). Every service bind-mounts both: the bundle over
# /etc/ssl/certs/ca-certificates.crt, and ca.crt hash-named as
# /etc/ssl/certs/<hash>.0 for old curl/openssl that resolves via CApath
# instead of the bundle. The hash comes from the CA subject, so it differs
# per project — sets CA_HASH in the caller's scope for renderTemplate.
# myDockersEmulate signs per-domain server certificates with this CA.
_myDockersEnsureCA() {
    local root="$1"
    local php_image="$2"
    local project ssldir generated=""
    project=$(basename "$root")
    ssldir="$root/mounted_shared_etc/ssl"

    command -v openssl >/dev/null 2>&1 || {
        echo "ERROR: openssl command not found, cannot create the project dev CA."
        return 1
    }

    mkdir -p "$ssldir"

    if [ ! -f "$ssldir/ca.crt" ]; then
        echo "Generating dev CA for $project (mounted_shared_etc/ssl/ca.crt, 10 years)"
        openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
            -keyout "$ssldir/ca.key" -out "$ssldir/ca.crt" \
            -subj "/CN=$project Dev CA/O=$project local dev" 2>/dev/null || {
            echo "ERROR: openssl failed to generate the dev CA."
            return 1
        }
        generated=1
    fi

    CA_HASH=$(openssl x509 -in "$ssldir/ca.crt" -noout -subject_hash)
    [ -n "$CA_HASH" ] || {
        echo "ERROR: could not compute the subject hash of $ssldir/ca.crt"
        return 1
    }

    # (Re)build the bundle when missing or when the CA was just generated.
    # Sources: the host's own bundle (Linux), else extracted from the PHP
    # base image (macOS has no ca-certificates.crt on the host).
    if [ ! -f "$root/mounted_shared_etc/ca-certificates.crt" ] || [ -n "$generated" ]; then
        local roots="$root/mounted_shared_etc/.ca-roots.tmp"

        if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
            cat /etc/ssl/certs/ca-certificates.crt > "$roots"
        else
            echo "No host CA bundle, extracting one from $php_image ..."
            _myDockersDaemonCheck || { rm -f "$roots"; return 1; }
            docker run --rm "$php_image" cat /etc/ssl/certs/ca-certificates.crt > "$roots" 2>/dev/null
        fi

        if ! grep -q "BEGIN CERTIFICATE" "$roots" 2>/dev/null; then
            rm -f "$roots"
            echo "ERROR: could not obtain a CA root bundle (host has no"
            echo "/etc/ssl/certs/ca-certificates.crt and docker extraction failed)."
            return 1
        fi

        cat "$roots" "$ssldir/ca.crt" > "$root/mounted_shared_etc/ca-certificates.crt"
        rm -f "$roots"
    fi

    return 0
}


# The subproject name becomes part of the compose service name, and compose
# uses that as the image tag — Docker rejects uppercase there ("repository
# name must be lowercase"). Catch it up front instead of failing the build.
_myDockersCheckSubProject() {
    local sub="$1"

    case "$sub" in
        *[A-Z]*)
            echo "SubProject must be lowercase — Docker image tags do not allow"
            echo "uppercase letters, so the build of the service would fail."
            echo
            echo "Instead of:  $sub"
            echo "use e.g.  :  $(printf '%s' "$sub" | tr '[:upper:]' '[:lower:]')"
            return 1
            ;;
        *[!a-z0-9_-]*|"")
            echo "SubProject may only contain lowercase letters, digits, _ and -:"
            echo "    $sub"
            return 1
            ;;
    esac
    return 0
}


# A malformed PHP_IMAGE (php7.0:apache instead of php:7.0-apache) slips a
# ':' into service and folder names, silently corrupting docker-compose.yml
# — myDockersBuild then fails with "Could not read services". Catch it up
# front (create, add, emulate) before anything is rendered.
_myDockersCheckPhpImage() {
    local image="$1" rest ver

    case "$image" in
        php:*apache*)
            rest="${image#php:}"
            case "$rest" in
                *[!a-z0-9.-]*) ;;       # bad characters — fall through
                *) return 0 ;;
            esac
            ;;
    esac

    echo "PHP_IMAGE must be an official php apache image, like php:8.4-apache"
    echo
    echo "Instead of:  $image"
    ver=$(printf '%s' "$image" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    [ -n "$ver" ] && echo "use e.g.  :  php:$ver-apache"
    echo
    echo "php apache images already pulled on this machine:"
    docker images --format '{{.Repository}}:{{.Tag}}' php 2>/dev/null | grep apache | sort -u | sed 's/^/    /' \
        || echo "    (none found, or docker not answering)"
    echo
    echo "Any php:<version>-apache tag from https://hub.docker.com/_/php works;"
    echo "php 7.1 and newer are tested, older builds are fail-soft (WARNING lines)."
    return 1
}


# db = user = password name of one subproject. Template sets with a hostdb/
# folder (LAlMP) share the HOST's MariaDB with every other such project, so
# their names carry the project too, lowercased to [a-z0-9_]
# (<project>_<php_id>_<sub>); container databases stay <php_id>_<sub>.
_myDockersDbName() {    # <template dir> <project> <php_id> <subproject>
    if [ -d "$1/hostdb" ]; then
        printf '%s_%s_%s' "$2" "$3" "$4" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_' '_'
    else
        printf '%s_%s' "$3" "$4"
    fi
}

# MariaDB allows 64 characters for a database name
_myDockersCheckDbName() {
    if [ ${#1} -gt 64 ]; then
        echo "Database name too long (${#1} characters, MariaDB allows 64):"
        echo "    $1"
        echo "Use a shorter project or subproject name."
        return 1
    fi
    return 0
}


# The address a container reaches this machine on (Docker's "host-gateway"):
# docker0, 172.17.0.1, on a native Docker Engine; 192.168.65.254 under Docker
# Desktop. Probed with a throwaway container rather than guessed.
_myDockersHostGateway() {
    local ip
    ip=$(docker run --rm --add-host mydockers-hostgw:host-gateway alpine \
            getent hosts mydockers-hostgw 2>/dev/null | awk '{ print $1; exit }')
    case "$ip" in
        *.*.*.*) echo "$ip"; return 0 ;;
    esac
    return 1
}


normalizePhpImage() {
    local image="$1"

    # php:8.5-apache -> php85apache
    image="${image#php:}"
    image="${image//./}"
    image="${image//-/}"

    echo "php$image"
}


# Render a template file to stdout, replacing __PLACEHOLDER__ tokens.
# Relies on the caller's PROJECT/SUB_PROJECT/PHP_ID/PHP_IMAGE/*_PORT variables.
renderTemplate() {
    local template="$1"

    sed -e "s|__PROJECT__|$PROJECT|g" \
        -e "s|__SUB_PROJECT_ID__|$SUB_PROJECT|g" \
        -e "s|__PHP_ID__|$PHP_ID|g" \
        -e "s|__PHP_IMAGE__|$PHP_IMAGE|g" \
        -e "s|__NET_PREFIX__|$NET_PREFIX|g" \
        -e "s|__WEB_OCTET__|$WEB_OCTET|g" \
        -e "s|__HTTP_PORT__|$HTTP_PORT|g" \
        -e "s|__MYSQL_PORT__|$MYSQL_PORT|g" \
        -e "s|__PMA_PORT__|$PMA_PORT|g" \
        -e "s|__CA_HASH__|$CA_HASH|g" \
        -e "s|__DB_NAME__|$DB_NAME|g" \
        -e "s|__EMULATED_DOMAIN__|$EMULATED_DOMAIN|g" \
        "$template"
}


# Make sure the project is a git repository (with .gitignore) and commit
# whatever has changed, on whatever branch is checked out.
myDockersCommit() {
    local root="$1"
    local message="$2"

    if ! command -v git >/dev/null 2>&1; then
        echo "WARNING: git not installed, skipping commit"
        return 0
    fi

    if [ ! -d "$root/.git" ]; then
        echo "Initializing git repository in $root"
        git -C "$root" init --quiet || { echo "WARNING: git init failed, skipping commit"; return 0; }
    fi

    if [ ! -f "$root/.gitignore" ]; then
        local tpl
        tpl=$(cat "$root/.myDockersTemplate" 2>/dev/null)
        cp "$MYDOCKERS_TEMPLATE_DIR/${tpl:-LAMP}/gitignore" "$root/.gitignore"
    fi

    git -C "$root" add -A

    if git -C "$root" diff --cached --quiet 2>/dev/null; then
        echo "git: nothing to commit"
        return 0
    fi

    if git -C "$root" commit --quiet -m "$message"; then
        echo "git: committed '$message'"
    else
        echo "WARNING: git commit failed"
    fi
}


# usage text of myDockersCreate
_myDockersCreateUsage() {
    echo "Usage:"
    echo "    myDockersCreate <Project> <SubProject> [PHP_IMAGE] [TEMPLATES] [HTTP_PORT] [MYSQL_PORT] [PHPMYADMIN_PORT]"
    echo
    echo "PHP_IMAGE defaults to php:8.4-apache, TEMPLATES to LAMP."
    echo "Ports:"
    echo "    none      the first free 10-port segment from ${MYDOCKERS_PORT_START:-8100}"
    echo "              (8100-8109, 8110-8119, ...): HTTP = its first port, database"
    echo "              and phpMyAdmin/Adminer the next two; myDockersAdd continues"
    echo "              from there. A segment is free when no MyDockers project"
    echo "              publishes and nothing on this machine listens on its ports."
    echo "    HTTP only database = HTTP+1, phpMyAdmin/Adminer = HTTP+2"
    echo "    LAlMP     uses this machine's own MariaDB: only HTTP_PORT counts,"
    echo "              MYSQL_PORT and PHPMYADMIN_PORT are ignored"
    echo
    echo "Example:"
    echo "    myDockersCreate moduledev prestashop91 php:8.5-apache"
    echo "    myDockersCreate myapp mysubproject php:8.4-apache LAPP"
    echo "    myDockersCreate myshop ps91 php:8.4-apache LAlMP"
    echo "    myDockersCreate moduledev prestashop91 php:8.5-apache LAMP 8890 8906 8902"
    echo
    echo "Available templates:"
    ls -d "$MYDOCKERS_TEMPLATE_DIR"/*/ 2>/dev/null | sed -e 's|/$||' -e 's|.*/|    |'
}


### create new Docker project from a template set (default: LAMP)
myDockersCreate() {

    if [ $# -lt 2 ]; then
        _myDockersCreateUsage
        return 1
    fi

    local PROJECT="$1"
    local SUB_PROJECT="$2"
    shift 2

    # [PHP_IMAGE] [TEMPLATES] [HTTP_PORT [MYSQL_PORT [PHPMYADMIN_PORT]]],
    # recognized by kind, so the old ports-first order still works:
    # numbers are ports in that order, php* the image, anything else the
    # template set
    local HTTP_PORT="" MYSQL_PORT="" PMA_PORT="" PHP_IMAGE="" TEMPLATE="" nports=0 a
    for a in "$@"; do
        case "$a" in
            "")
                _myDockersCreateUsage
                return 1
                ;;
            *[!0-9]*)
                case "$a" in
                    php*) [ -z "$PHP_IMAGE" ] && PHP_IMAGE="$a" || { _myDockersCreateUsage; return 1; } ;;
                    *)    [ -z "$TEMPLATE" ]  && TEMPLATE="$a"  || { _myDockersCreateUsage; return 1; } ;;
                esac
                ;;
            *)
                nports=$((nports + 1))
                case "$nports" in
                    1) HTTP_PORT="$a" ;;
                    2) MYSQL_PORT="$a" ;;
                    3) PMA_PORT="$a" ;;
                    *) _myDockersCreateUsage; return 1 ;;
                esac
                ;;
        esac
    done
    PHP_IMAGE="${PHP_IMAGE:-php:8.4-apache}"
    TEMPLATE="${TEMPLATE:-LAMP}"

    _myDockersCheckSubProject "$SUB_PROJECT" || return 1
    _myDockersCheckPhpImage "$PHP_IMAGE" || return 1
    local PHP_ID
    PHP_ID=$(normalizePhpImage "$PHP_IMAGE")

    local ROOT="$HOME/MyDockers/$PROJECT"
    local TPL="$MYDOCKERS_TEMPLATE_DIR/$TEMPLATE"
    local WEB_DIR="${PHP_ID}_${SUB_PROJECT}_web"
    local SRC_DIR="${PHP_ID}_${SUB_PROJECT}_src"

    if [ ! -d "$TPL" ]; then
        echo "Templates folder not found:"
        echo "    $TPL"
        echo
        echo "Available templates:"
        ls -d "$MYDOCKERS_TEMPLATE_DIR"/*/ 2>/dev/null | sed -e 's|/$||' -e 's|.*/|    |'
        return 1
    fi

    # ports left out after HTTP_PORT follow it (+1, +2); host-database sets
    # (LAlMP) have no database or admin container and ignore those two
    if [ -d "$TPL/hostdb" ]; then
        if [ -n "$MYSQL_PORT$PMA_PORT" ]; then
            echo "NOTE: $TEMPLATE uses this machine's MariaDB — MYSQL_PORT/PHPMYADMIN_PORT ignored."
        fi
        MYSQL_PORT="" PMA_PORT=""
    elif [ -n "$HTTP_PORT" ]; then
        MYSQL_PORT="${MYSQL_PORT:-$((HTTP_PORT + 1))}"
        PMA_PORT="${PMA_PORT:-$((HTTP_PORT + 2))}"
    fi

    local DB_NAME
    DB_NAME=$(_myDockersDbName "$TPL" "$PROJECT" "$PHP_ID" "$SUB_PROJECT")
    _myDockersCheckDbName "$DB_NAME" || return 1

    if [ -d "$ROOT" ]; then
        echo "Project already exists:"
        echo "    $ROOT"
        return 1
    fi

    # host ports: given ones must be free, otherwise take a free segment
    local taken base
    if [ "$nports" -eq 0 ]; then
        base=$(_myDockersFreePortSegment) || return 1
        HTTP_PORT="$base"
        if [ ! -d "$TPL/hostdb" ]; then
            MYSQL_PORT=$((base + 1))
            PMA_PORT=$((base + 2))
        fi
        echo "Port segment $base-$((base + 9)): HTTP $HTTP_PORT${MYSQL_PORT:+, database $MYSQL_PORT}${PMA_PORT:+, admin $PMA_PORT}"
    else
        taken=$(_myDockersPortsTaken $HTTP_PORT $MYSQL_PORT $PMA_PORT)
        if [ -n "$taken" ]; then
            echo "Port(s) already in use (by a MyDockers project, or listening on this machine):"
            echo "    $taken"
            echo "Leave the ports out to get a free segment automatically."
            return 1
        fi
    fi

    # static-IP network for this project: db .10, phpmyadmin/adminer .11,
    # web services .101 and up (myDockersAdd continues the sequence)
    local NET_PREFIX WEB_OCTET=101
    NET_PREFIX=$(_myDockersNextSubnet) || return 1

    echo "Creating $ROOT (network $NET_PREFIX.0/24)"

    # dev CA + CA bundle first: the compose templates bind-mount both into
    # every service, and renderTemplate needs CA_HASH ("Project already
    # exists" was checked above, so on failure the fresh dir can go)
    local CA_HASH
    _myDockersEnsureCA "$ROOT" "$PHP_IMAGE" || { rm -rf "$ROOT"; return 1; }

    # docker exec -it -u myproject myproject_web bash

    mkdir -p "$ROOT/home/$PROJECT" "$ROOT/$WEB_DIR" "$ROOT/$SRC_DIR"

    # data folders only for the databases this template set contains
    [ -d "$TPL/mariadb" ]  && mkdir -p "$ROOT/data/mysql"
    [ -d "$TPL/postgres" ] && mkdir -p "$ROOT/data/postgres"

    # remember the template set; myDockersAdd renders from the same one
    echo "$TEMPLATE" > "$ROOT/.myDockersTemplate"

    renderTemplate "$TPL/docker-compose.yml"  > "$ROOT/docker-compose.yml"
    renderTemplate "$TPL/web-service.yml"    >> "$ROOT/docker-compose.yml"
    renderTemplate "$TPL/php/Dockerfile"      > "$ROOT/$WEB_DIR/Dockerfile"

    # render every other file the template set contains, keeping paths
    local tfile dest
    for tfile in $(cd "$TPL" && find . -type f | sed 's|^\./||'); do
        case "$tfile" in
            gitignore|docker-compose.yml|web-service.yml|php/Dockerfile|*.DS_Store)
                continue
                ;;
            mounted_etc/vhost-ssl.conf)
                # emulator-only chunk, rendered by myDockersEmulate
                continue
                ;;
        esac

        case "$tfile" in
            */init.sql)
                # per-subproject database init file
                dest="$ROOT/${tfile%/init.sql}/init/init-${DB_NAME}.sql"
                ;;
            mounted_etc/*)
                # per-service config folder, named after the sub project
                dest="$ROOT/mounted_etc/$SUB_PROJECT/${tfile#mounted_etc/}"
                ;;
            *)
                dest="$ROOT/$tfile"
                ;;
        esac

        mkdir -p "$(dirname "$dest")"
        renderTemplate "$TPL/$tfile" > "$dest"

        case "$dest" in
            *.sh) chmod +x "$dest" ;;
        esac
    done

    touch "$ROOT/$SRC_DIR/index.php"

    _myDockersWriteHosts "$ROOT"

    _myDockersWriteCredentials "$ROOT" "$SUB_PROJECT" "$DB_NAME" "$HTTP_PORT"

    myDockersCommit "$ROOT" "myDockersCreate $PROJECT $SUB_PROJECT ($PHP_IMAGE, $TEMPLATE)"

    if [ -d "$TPL/hostdb" ]; then
        # the host's MariaDB is already running: create the database now
        echo
        myDockersInitDBs "$PROJECT"

        echo
        echo "Done."
        echo
        echo "Database (on this machine's localhost MariaDB): $DB_NAME, user = password = $DB_NAME"
        echo "All logins: $ROOT/credentials.txt"
        echo
        echo "Next:"
        echo "    myDockersBuild $PROJECT && cd $ROOT && docker compose up -d"
        return 0
    fi

    echo
    echo "Done."
    echo
    echo "All logins: $ROOT/credentials.txt"
    echo
    echo "Next (build, start, create the databases):"
    echo "    myDockersBuild $PROJECT && cd $ROOT && docker compose up -d && myDockersInitDBs $PROJECT"

    if [ -d "$TPL/postgres" ]; then
        echo "Adminer login (password: $PROJECT):"
        echo "    http://localhost:$PMA_PORT/?pgsql=pgdb&username=$PROJECT&db=$PROJECT"
    fi

}
