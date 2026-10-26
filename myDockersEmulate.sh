
# Load shared helpers (renderTemplate, _myDockersEnsureCA, myDockersCommit,
# _myDockersWriteHosts, MYDOCKERS_TEMPLATE_DIR) and myDockersAdd
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _myDockersEmulateSource="${BASH_SOURCE[0]}"
else
    _myDockersEmulateSource="${(%):-%x}"
fi
_myDockersEmulateDir="$(cd "$(dirname "$_myDockersEmulateSource")" && pwd)"
source "$_myDockersEmulateDir/myDockersCreate.sh"
source "$_myDockersEmulateDir/myDockersAdd.sh"
unset _myDockersEmulateSource _myDockersEmulateDir


### turn a subproject into an HTTPS emulator of a real API domain:
### its Apache answers https://<Domain>/ with a certificate signed by the
### project dev CA, and every container in the project resolves <Domain>
### to the emulator and trusts the certificate chain.
myDockersEmulate() {

    if [ $# -lt 3 ] || [ $# -gt 4 ]; then
        echo "Usage:"
        echo "    myDockersEmulate <Project> <SubProject> <Domain> [PHP_IMAGE]"
        echo
        echo "Example:"
        echo "    myDockersEmulate ahcoPresta emulate_paytrail_psp services.paytrail.com php:8.5-apache"
        echo
        echo "Adds the subproject first (myDockersAdd) if it does not exist yet."
        echo "Run again with another Domain to emulate several APIs from the"
        echo "same subproject (one *:443 vhost + certificate per domain)."
        return 1
    fi

    local PROJECT="$1"
    local SUB_PROJECT="$2"
    local DOMAIN="$3"
    local PHP_IMAGE="${4:-php:8.4-apache}"

    _myDockersCheckSubProject "$SUB_PROJECT" || return 1
    _myDockersCheckPhpImage "$PHP_IMAGE" || return 1

    # bare lowercase hostname only — no scheme, no path, no port
    case "$DOMAIN" in
        *[!a-z0-9.-]*|""|-*|.*|*-|*.)
            echo "Domain must be a bare lowercase hostname (a-z, 0-9, dots, dashes):"
            echo "    $DOMAIN"
            echo
            echo "e.g.  services.paytrail.com   (no https://, no path, no port)"
            return 1
            ;;
    esac

    local ROOT="$HOME/MyDockers/$PROJECT"
    local COMPOSE="$ROOT/docker-compose.yml"
    local CONTAINER="${PROJECT}_${SUB_PROJECT}_web"

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

    # the emulator is a normal web service — add it if it is not there yet
    if ! grep -q "container_name: $CONTAINER" "$COMPOSE"; then
        myDockersAdd "$PROJECT" "$SUB_PROJECT" "$PHP_IMAGE" || return 1
    fi

    # template set, for the vhost-ssl.conf chunk
    local TEMPLATE TPL
    TEMPLATE=$(cat "$ROOT/.myDockersTemplate" 2>/dev/null)
    TPL="$MYDOCKERS_TEMPLATE_DIR/${TEMPLATE:-LAMP}"

    if [ ! -f "$TPL/mounted_etc/vhost-ssl.conf" ]; then
        echo "Template set ${TEMPLATE:-LAMP} has no mounted_etc/vhost-ssl.conf:"
        echo "    $TPL"
        return 1
    fi

    local ETC="$ROOT/mounted_etc/$SUB_PROJECT"

    if [ ! -f "$ETC/vhost.conf" ]; then
        echo "No per-service config folder for $SUB_PROJECT:"
        echo "    $ETC/vhost.conf"
        echo
        echo "This service predates the mounted_etc convention and cannot be"
        echo "turned into an emulator — add a fresh subproject instead:"
        echo "    myDockersEmulate $PROJECT ${SUB_PROJECT}2 $DOMAIN $PHP_IMAGE"
        return 1
    fi

    # project dev CA (also bootstraps projects created before the CA feature)
    local CA_HASH
    _myDockersEnsureCA "$ROOT" "$PHP_IMAGE" || return 1

    # server certificate for the domain, signed by the project CA (SAN, 5 y)
    local SSL_DIR="$ETC/ssl"
    mkdir -p "$SSL_DIR"

    if [ ! -f "$SSL_DIR/$DOMAIN.crt" ]; then
        echo "Generating certificate for $DOMAIN (signed by the $PROJECT dev CA, 5 years)"
        openssl req -new -newkey rsa:2048 -nodes \
            -keyout "$SSL_DIR/$DOMAIN.key" -out "$SSL_DIR/$DOMAIN.csr" \
            -subj "/CN=$DOMAIN" 2>/dev/null \
        && printf 'subjectAltName=DNS:%s\n' "$DOMAIN" > "$SSL_DIR/$DOMAIN.ext" \
        && openssl x509 -req -sha256 -days 1825 \
            -in "$SSL_DIR/$DOMAIN.csr" \
            -CA "$ROOT/mounted_shared_etc/ssl/ca.crt" \
            -CAkey "$ROOT/mounted_shared_etc/ssl/ca.key" \
            -CAcreateserial \
            -extfile "$SSL_DIR/$DOMAIN.ext" \
            -out "$SSL_DIR/$DOMAIN.crt" 2>/dev/null \
        || {
            echo "ERROR: openssl failed to create the server certificate."
            rm -f "$SSL_DIR/$DOMAIN.key" "$SSL_DIR/$DOMAIN.csr" "$SSL_DIR/$DOMAIN.ext" "$SSL_DIR/$DOMAIN.crt"
            return 1
        }
        rm -f "$SSL_DIR/$DOMAIN.csr" "$SSL_DIR/$DOMAIN.ext"
    fi

    # *:443 vhost for the domain (skip if this domain already has one)
    if ! awk -v d="$DOMAIN" '$1 == "ServerName" && $2 == d { found = 1 } END { exit !found }' \
            "$ETC/vhost.conf"; then
        local EMULATED_DOMAIN="$DOMAIN"
        {
            echo ""
            renderTemplate "$TPL/mounted_etc/vhost-ssl.conf"
        } >> "$ETC/vhost.conf"
    fi

    # retro-fit the two CA mounts on services that predate the CA feature:
    # insert after each hosts mount whose next line is not already the CA
    # bundle mount (services without the hosts mount are older still and
    # stay out, same rule as the hosts file itself)
    awk -v ca="      - ./mounted_shared_etc/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro" \
        -v ha="      - ./mounted_shared_etc/ssl/ca.crt:/etc/ssl/certs/$CA_HASH.0:ro" '
        {
            if (pending && $0 !~ /ca-certificates\.crt/) { print ca; print ha }
            pending = ($0 ~ /mounted_shared_etc\/hosts:\/etc\/hosts:ro/)
            print
        }
        END { if (pending) { print ca; print ha } }' \
        "$COMPOSE" > "$COMPOSE.tmp" && mv "$COMPOSE.tmp" "$COMPOSE"

    # mount the emulator's cert dir into its own service block only, right
    # after the hash-named CA mount (which the retro-fit above guarantees)
    if ! grep -q "mounted_etc/$SUB_PROJECT/ssl:" "$COMPOSE"; then
        awk -v target="container_name: $CONTAINER" \
            -v m="      - ./mounted_etc/$SUB_PROJECT/ssl:/etc/apache2/ssl-mydockers:ro" '
            index($0, target) { in_target = 1 }
            /container_name:/ && !index($0, target) { in_target = 0 }
            { print }
            in_target && /mounted_shared_etc\/ssl\/ca.crt:/ { print m; in_target = 0 }' \
            "$COMPOSE" > "$COMPOSE.tmp" && mv "$COMPOSE.tmp" "$COMPOSE"
    fi

    # mod_ssl for services built before it was in the Dockerfile template
    # (build dir taken from the service's own build context in the compose)
    local webdir dockerfile
    webdir=$(awk -v target="container_name: $CONTAINER" '
        $1 == "context:" { c = $2 } index($0, target) { print c; exit }' "$COMPOSE")
    dockerfile="$ROOT/${webdir#./}/Dockerfile"
    if [ -f "$dockerfile" ] && ! grep -q "a2enmod ssl" "$dockerfile"; then
        printf '\nRUN a2enmod ssl || echo "WARNING: could not enable mod_ssl"\n' >> "$dockerfile"
    fi

    # redirect the domain to the emulator in every container
    _myDockersWriteHosts "$ROOT"

    myDockersCommit "$ROOT" "myDockersEmulate $SUB_PROJECT ($DOMAIN)"

    echo
    echo "Done. $SUB_PROJECT now emulates https://$DOMAIN/"
    echo
    echo "Next:"
    echo "    myDockersBuild $PROJECT && cd $ROOT && docker compose up -d"
    echo
    echo "Verify from any other container of the project:"
    echo "    docker exec <container> curl -s https://$DOMAIN/"
}
