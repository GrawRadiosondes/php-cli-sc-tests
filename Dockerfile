FROM php:8.3-cli

# apt update & apt-utils
RUN apt-get update && apt-get install -y apt-utils

# allow nodejs lts to be installed via apt
# https://github.com/nodesource/distributions#installation-instructions
RUN curl -sL https://deb.nodesource.com/setup_lts.x  | bash -

# install cypress dependencies
# https://docs.cypress.io/guides/continuous-integration/introduction#Dependencies
RUN apt-get install -y \
    libgtk2.0-0 \
    libgtk-3-0 \
    libgbm-dev \
    libnotify-dev \
    libgconf-2-4 \
    libnss3 \
    libxss1 \
    libasound2 \
    libxtst6 \
    xauth \
    xvfb \
    nodejs

# install php extension dependencies
RUN apt-get install -y \
    libzip-dev \
    libicu-dev \
    libpq-dev

# install php extensions
RUN docker-php-ext-install pdo_mysql
RUN docker-php-ext-install pgsql
RUN docker-php-ext-install pdo_pgsql
RUN docker-php-ext-install zip
RUN docker-php-ext-install intl

# install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# install xdebug
RUN pecl install xdebug
RUN docker-php-ext-enable xdebug
RUN echo xdebug.mode=coverage > /usr/local/etc/php/conf.d/xdebug.ini

# install git
RUN apt-get install -y git

# clear apt cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# increase memory limit
RUN echo 'memory_limit = 1G' >> "$PHP_INI_DIR/conf.d/memory-limit.ini";
