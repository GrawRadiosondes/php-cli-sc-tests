FROM php:8.2-cli

# apt update & apt-utils
RUN apt-get update && apt-get install -y apt-utils

# apt install php extension dependencies
RUN apt-get install -y \
    libzip-dev

# install php extensions
RUN docker-php-ext-install \
    pdo_mysql \
    zip

# install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# install xdebug
RUN pecl install xdebug
RUN docker-php-ext-enable xdebug
RUN echo xdebug.mode=coverage > /usr/local/etc/php/conf.d/xdebug.ini

# clear apt cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
