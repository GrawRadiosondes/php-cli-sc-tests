FROM php:8.5-cli

#########################################################
## prepare package manager and install general tooling ##
#########################################################

# apt update & apt-utils
RUN apt update
RUN apt install -y apt-utils

# install git
RUN apt install -y git

# install nmap & tree (debug purposes)
RUN apt install -y nmap tree


###############
## setup php ##
###############

# install php extension dependencies
RUN apt install -y libicu-dev
RUN apt install -y libjpeg-dev
RUN apt install -y libpng-dev
RUN apt install -y libpq-dev
RUN apt install -y libzip-dev

# install php extensions
RUN docker-php-ext-configure gd --with-jpeg
RUN docker-php-ext-install -j$(nproc) \
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

# install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# install xdebug
RUN pecl install xdebug
RUN docker-php-ext-enable xdebug
RUN echo xdebug.mode=coverage > "$PHP_INI_DIR/conf.d/xdebug.ini"

# increase memory limit
RUN echo 'memory_limit = 1G' >> "$PHP_INI_DIR/conf.d/memory-limit.ini"


###############
## setup bun ##
###############

COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

# node-gyp is required by tree-sitter
RUN apt install -y python3
RUN bun install -g node-gyp


########################
## install playwright ##
########################

RUN bunx playwright install --with-deps


########################################
## setup nginx as https reverse proxy ##
########################################

# install nginx
RUN apt install -y gnupg2
RUN apt install -y ca-certificates
RUN apt install -y lsb-release
RUN apt install -y dirmngr
RUN apt install -y apt-transport-https
RUN curl -fSsL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null
RUN echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list
RUN echo "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx
RUN apt update
RUN apt install -y nginx

# setup mkcert
RUN apt install -y libnss3-tools
RUN curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
RUN chmod +x mkcert-v*-linux-amd64
RUN cp mkcert-v*-linux-amd64 /usr/local/bin/mkcert
RUN mkcert -install
RUN update-ca-certificates --fresh

# generate certs
RUN mkdir /etc/nginx/certs
RUN mkcert -key-file /etc/nginx/certs/soketi-key.pem -cert-file /etc/nginx/certs/soketi.pem soketi
RUN mkcert -key-file /etc/nginx/certs/localhost-key.pem -cert-file /etc/nginx/certs/localhost.pem localhost coverage.localhost

# configure nginx
COPY sounding-center/sail/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf
COPY sounding-center/sail/nginx/conf.d/localhost.conf /etc/nginx/conf.d/localhost.conf
COPY sounding-center/sail/nginx/conf.d/soketi.conf /etc/nginx/conf.d/soketi.conf


#####################
## finishing steps ##
#####################

# clear apt cache
RUN apt clean && rm -rf /var/lib/apt/lists/*

# if the nginx https reverse proxy is needed, just run `nginx` to start the deamon
