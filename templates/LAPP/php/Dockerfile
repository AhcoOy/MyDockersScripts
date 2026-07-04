FROM __PHP_IMAGE__



RUN if [ -n "__PROJECT__" ] && ! id "__PROJECT__" >/dev/null 2>&1; then \
      useradd -m -s /bin/bash "__PROJECT__" && \
      echo "__PROJECT__:__PROJECT__" | chpasswd; \
    fi

# Old Debian releases (stretch, buster, ...) have moved to
# archive.debian.org; if the normal apt update fails, rewrite the
# sources and retry so old PHP images keep working.
RUN apt-get update \
 || { echo "WARNING: apt-get update failed, switching to archive.debian.org"; \
      sed -i -e 's|deb.debian.org|archive.debian.org|g' \
             -e 's|security.debian.org|archive.debian.org|g' \
             -e '/-updates/d' /etc/apt/sources.list; \
      echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive; \
      apt-get update || echo "WARNING: apt-get update still failing, continuing anyway"; }

# Install every apt package that is available on this base image;
# warn about the rest instead of failing the build.
RUN failed=""; \
    for pkg in \
        libicu-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libzip-dev \
        libpq-dev \
        unzip \
        git \
        rsync \
        curl \
        wget \
        vim \
        nano \
        htop \
        tree \
        less \
        procps \
        lsof \
        net-tools \
        iputils-ping \
        dnsutils \
        openssh-client \
        postgresql-client \
        sqlite3 \
        jq \
        ripgrep \
    ; do \
        apt-get install -y "$pkg" || failed="$failed $pkg"; \
    done; \
    if [ -n "$failed" ]; then echo "WARNING: could not install apt packages:$failed"; fi

# gd configure flags changed in PHP 7.4; try the new syntax first,
# fall back to the pre-7.4 one.
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 || docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
 || echo "WARNING: could not configure gd"

# Install every PHP extension that builds on this image; skip the ones
# already compiled in (e.g. opcache on new images), warn about the rest.
RUN failed=""; \
    for ext in intl pdo pdo_pgsql pgsql gd zip opcache; do \
        if php -m | grep -qi "^\(Zend \)\?$ext\$"; then \
            echo "$ext already installed, skipping"; \
        else \
            docker-php-ext-install "$ext" || failed="$failed $ext"; \
        fi; \
    done; \
    if [ -n "$failed" ]; then echo "WARNING: could not install PHP extensions:$failed"; fi

RUN a2enmod rewrite || echo "WARNING: could not enable mod_rewrite"

# wkhtmltopdf — CakePdf's WkHtmlToPdf engine needs it (invoice PDFs,
# src/Domain/ToPdfTrait.php). Official headless build; Debian's own package
# is compiled against unpatched Qt and needs an X server.
# The .deb targets bookworm, so older bases just warn.
RUN ARCH=$(dpkg --print-architecture); \
    { curl -fsSL -o /tmp/wkhtmltox.deb \
        "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb" \
      && apt-get install -y /tmp/wkhtmltox.deb \
      && wkhtmltopdf --version; } \
    || echo "WARNING: could not install wkhtmltopdf"; \
    rm -f /tmp/wkhtmltox.deb

 # Composer (composer:2 needs PHP >= 7.2.5; on older PHP fall back to 2.2 LTS)
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN composer --version >/dev/null 2>&1 \
 || { echo "composer needs a newer PHP, using Composer 2.2 LTS instead"; \
      curl -fsSL -o /usr/local/bin/composer https://getcomposer.org/download/latest-2.2.x/composer.phar \
      && chmod +x /usr/local/bin/composer \
      && composer --version; } \
 || echo "WARNING: composer does not work on this PHP version"

RUN composer global require \
        phpunit/phpunit \
        phpstan/phpstan \
        friendsofphp/php-cs-fixer \
    || echo "WARNING: could not install composer global tools"

# javascript, nodejs, quasar (needs a recent Debian base; warns on old ones)
RUN { apt-get install -y ca-certificates gnupg \
      && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
      && apt-get install -y nodejs \
      && corepack enable \
      && npm install -g @quasar/cli; } \
    || echo "WARNING: could not install nodejs / quasar cli"


RUN git config --system pull.rebase false || echo "WARNING: could not set git config"

RUN mkdir -p /workspace
WORKDIR /var/www/html

########## make Quasar build work with openssl 3.0, see
ENV NODE_OPTIONS=--openssl-legacy-provider

