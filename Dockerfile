# CI image for GrawRadiosondes/grawgo.
#
# Built and published by .github/workflows/publish.yml as
# docker.io/grawradiosondes/grawgo-ci:<semver>. See README.md for the contract.
#
# Scope is deliberately narrow: everything four grawgo CI jobs need before
# `composer install` (bun, vite build, pest, phpstan, phpcs) and nothing else.
# No nginx, no mkcert, no baked certificates, no browser binaries — those either
# belong to the Sail compose stack or are installed at job runtime.
#
# Every input is pinned by digest so a rebuild is reproducible and Renovate can
# open a bump pull request for each one.

FROM php:8.5-cli@sha256:0e17ef0527f296b85bfe4cfb5219b29cafc37224857ed73d28628ea142930ac8

# One apt transaction: the index can never go stale relative to the installs
# below it, which is what the previous ~20 separate `apt install` layers risked.
#
#   git                       actions/checkout and composer's VCS downloader
#   unzip                     composer --prefer-dist (avoids the ZipArchive fallback notice)
#   python3                   node-gyp, which tree-sitter builds with
#   lib*-dev                  build inputs for the extensions in the next layer:
#                             icu → intl, jpeg/png/webp → gd, pq → pdo_pgsql+pgsql, zip → zip
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        libicu-dev \
        libjpeg-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libzip-dev \
        python3 \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Tracks the platform requirements of grawgo's composer.lock — its own ext-* requires plus
# the ones its dependencies pull in (ext-sockets arrives that way). `composer check-platform-reqs`
# runs as the first step of grawgo's build job and fails loudly if the two drift.
#
# pcntl, pdo_mysql and pgsql are not required by the lock file. pcntl is what `pest --parallel`
# needs; the other two are kept because dropping them buys nothing and would break any job that
# ever points at a MySQL or a raw pgsql connection.
#
# curl, fileinfo, mbstring, xml, sqlite3, pdo_sqlite and pdo are already compiled
# into php:*-cli and must not be listed here — docker-php-ext-install would fail on
# them. ext-sqlite3 in particular is what grawgo's whole `sqlite_testing` suite runs
# on; its absence from this list is inherited, not an oversight.
RUN docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        gd \
        intl \
        mysqli \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        sockets \
        zip

# pcov, not xdebug. CI only ever collects line coverage (`pest --coverage --min=100`)
# and never step-debugs, and pcov is substantially faster at exactly that. The nix
# build path made this choice in March 2026; the Dockerfile never followed.
RUN pecl install pcov \
    && docker-php-ext-enable pcov \
    && rm -rf /tmp/pear

RUN { \
        echo 'memory_limit = 1G'; \
        echo 'pcov.enabled = 1'; \
        echo 'pcov.directory = app'; \
    } > "$PHP_INI_DIR/conf.d/grawgo-ci.ini"

COPY --from=composer:2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040 /usr/bin/composer /usr/local/bin/composer

COPY --from=oven/bun:1@sha256:5ff609364c049b54eb0ff560ec96319729a972078ef2c755d758f0c6ef89c2d6 /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

# node is here only because node-gyp (used when tree-sitter builds) shells out to it;
# grawgo's own scripts all run under bun. The major is pinned rather than `setup_lts.x`
# so a new LTS cannot roll into the image unannounced.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && bun install -g node-gyp

# Playwright's OS libraries only — not the browser binaries. `install-deps` needs root
# and apt, so it belongs in the image; the chromium binary does not, because grawgo pins
# playwright to an exact version (its renovate.json disables auto-bumps to keep NixOS devs
# in lockstep with nixpkgs) and baking browsers would couple every playwright bump to an
# image rebuild. grawgo's tests job installs the browser itself. Left unversioned on
# purpose, matching grawgo's .devcontainer/Dockerfile: the dependency list is what is
# wanted, not a particular playwright release.
RUN apt-get update \
    && bunx playwright install-deps \
    && rm -rf /var/lib/apt/lists/*
