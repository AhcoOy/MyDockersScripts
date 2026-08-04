# Release V3.1.0
HTTPS API emulation — per-project dev CA, myDockersEmulate (2026-08-04)

### myDockersEmulate (new command)
- `myDockersEmulate <Project> <SubProject> <Domain> [PHP_IMAGE]` turns a
  subproject into an HTTPS emulator of a real API domain: its Apache serves
  `https://<Domain>/` with a certificate every container in the project
  trusts, and every container resolves `<Domain>` to the emulator's static
  IP — hardcoded third-party HTTPS URLs (payment providers, shipping APIs,
  ...) land on your mock implementation with full certificate validation
- Adds the subproject first (via `myDockersAdd`) when it does not exist yet
- Re-runnable with more domains: one `*:443` vhost + one certificate per
  domain, SNI picks the right one
- Server certificates (SAN, 5 years) live in `mounted_etc/<subproject>/ssl/`,
  mounted to `/etc/apache2/ssl-mydockers`
- Projects created before 3.1 get the dev CA and its mounts retro-fitted on
  the fly; services predating the `mounted_etc` convention cannot become
  emulators (the command explains what to do instead)

### myDockersCreate / myDockersAdd
- Every project now gets a dev CA at create time (`mounted_shared_etc/ssl/`,
  10 years, subject `CN=<Project> Dev CA`) plus a CA bundle
  `mounted_shared_etc/ca-certificates.crt` (distro roots + dev CA; on macOS
  the roots are extracted via `docker run <php_image>`)
- Both are mounted into every service: the bundle over
  `/etc/ssl/certs/ca-certificates.crt`, and the CA also hash-named as
  `/etc/ssl/certs/<hash>.0` so old curl/openssl (PHP 7.x included) validates
  via CApath as well
- `myDockersAdd` bootstraps the CA for pre-3.1 projects; their existing
  services keep running unchanged, new services get the mounts
- The generated hosts file now also redirects every emulated domain to its
  emulator's IP — domains are discovered from the vhost configs, so the
  redirects survive regeneration; custom entries below the marker line are
  still kept

### Templates (LAMP and LAPP)
- New `mounted_etc/vhost-ssl.conf` chunk, rendered only by `myDockersEmulate`
- `a2enmod ssl` (fail-soft) in the php Dockerfiles
- CA mounts added to every service in `web-service.yml` and
  `docker-compose.yml` (db/pgdb and phpMyAdmin/Adminer included)

### README
- New "Emulating HTTPS APIs" section
- `myDockersDown` documented (was missing from the commands table)

# Release V3.0.0
Static IPs, hostnames, shared hosts file, SSH between containers (2026-07-21)

### myDockersCreate
- Each project receives its own network using the next available
  `172.30.N.0/24` subnet
- Static IP assignment: databases at `.10`, admin tools at `.11`, web
  services at `.101+`
- Web service hostnames match subproject names for direct container
  communication
- Per-subproject configuration stored in `mounted_etc/<subproject>/`
- Generates shared hosts file with all hostnames and static IPs
- Validates subproject names to lowercase only

### myDockersAdd
- New services continue IP sequences and append to shared hosts file
- Custom entries in hosts file below marker line persist through
  regeneration
- Pre-3.0 projects upgrade automatically with network blocks and static IPs
  for new services
- Applies same lowercase validation as myDockersCreate

### Templates (LAMP and LAPP)
- Web containers run SSH alongside Apache
- All services resolve via shared hosts file without port exposure
- MariaDB uses `--skip-ssl` flag for compatibility
- Tested with 4-subproject LAMP (PHP 8.5/8.1/7.2/7.1) and 2-subproject LAPP
  stacks

# Release V2.0.0
MyDockersScripts 2.0 — template sets, PostgreSQL (LAPP) stacks, engine-aware tooling (2026-07-04)

### Template Sets — LAMP and LAPP
Command syntax now includes template selection parameter. New LAPP stack
provides a full Linux + Apache + PostgreSQL + PHP stack with postgres:17,
Adminer, and idempotent initialization SQL.

### myDockersCreate
- Template parameter selection with validation
- Removed hardcoded MariaDB folder paths
- Generates Adminer login URLs for PostgreSQL projects
- Prints "Next:" command chain guidance

### myDockersAdd
- Optional template parameter; defaults to project's recorded template
- Validates non-LAMP projects with example syntax

### myDockersInitDBs
- Engine-aware initialization for both MariaDB and PostgreSQL
- Waits for stable server connection before executing
- Verifies database existence after each SQL init file

### myDockersHints
- Stack-aware: displays only relevant containers and tools
- PostgreSQL login details and Adminer URLs included

### myDockersBuild
- Detects wedged Docker daemon with 8-second watchdog
- Provides restart guidance for daemon issues
- Displays command chain after successful builds

### New features
- `myDockersReload` command for refreshing shell scripts
- Example use cases: `useCase.sh` (4× PrestaShop on LAMP) and `useCase2.sh`
  (2× PHP on LAPP)
- Rewritten README covering template sets and both stacks

# Release V1.0.1
MyDockersScripts 1.0.1 — myDockersHints overhaul (2026-07-04)

### myDockersHints
- Subproject-aware hints: commands now target actual containers like
  `<Project>_<SubProject>_web`
- Project overview: running without arguments scans projects, lists web
  containers with status
- Input validation: unknown projects fail with clear error and valid
  alternatives listed
- References `myDockersBuild`, `myDockersInitDBs`, and `myDockersAdd` in
  cheat sheet

# Release V1.0.0
MyDockersScripts 1.0 — first public release (2026-07-04)

Shell commands for running multi-PHP LAMP development stacks on Docker:

- `myDockersCreate`: new project setup from templates
- `myDockersAdd`: add subprojects with any PHP version (7.1–8.5)
- `myDockersBuild`: build all services with per-service logs
- `myDockersInitDBs`: create and verify per-subproject databases
- `myDockersHints`: docker command cheat sheet

Generated projects are git repositories with automatic commits. Supports
old PHP images via archive.debian.org. License: MIT © Ahco Oy.
