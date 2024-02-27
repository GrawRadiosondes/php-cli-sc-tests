FROM php:8.3-cli

##############################################
## prepare package manager and install general tooling ##
##############################################

# apt update & apt-utils
RUN apt update
RUN apt install -y apt-utils

# install git
RUN apt install -y git

# install nmap (dev purposes)
RUN apt install -y nmap

# install security lib e.g. needed by cypress and mkcert
RUN apt install -y libnss3


################
## setup cypress ##
################

# allow nodejs lts to be installed via apt
# https://github.com/nodesource/distributions#installation-instructions
RUN curl -sL https://deb.nodesource.com/setup_18.x  | bash -

# install cypress dependencies
# https://docs.cypress.io/guides/continuous-integration/introduction#Dependencies
RUN apt install -y \
    libgtk2.0-0 \
    libgtk-3-0 \
    libgbm-dev \
    libnotify-dev \
    libgconf-2-4 \
    libxss1 \
    libasound2 \
    libxtst6 \
    xauth \
    xvfb \
    nodejs


#############
## setup php ##
#############

# install php extension dependencies
RUN apt install -y \
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

# increase memory limit
RUN echo 'memory_limit = 1G' >> "$PHP_INI_DIR/conf.d/memory-limit.ini";


###############
## setup soketi ##
###############

# install soketi and pm2 to run it
RUN npm install -g pm2 @soketi/soketi

# install nginx
RUN apt install -y \
    gnupg2 \
    ca-certificates \
    lsb-release \
    dirmngr \
    software-properties-common \
    apt-transport-https
RUN curl -fSsL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null
RUN echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list
RUN echo "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx
RUN apt update
RUN apt install -y nginx

# setup mkcert and generate certs
RUN NONINTERACTIVE=1 && /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
RUN /home/linuxbrew/.linuxbrew/bin/brew install mkcert
RUN /home/linuxbrew/.linuxbrew/bin/mkcert -install
RUN mkdir /etc/nginx/certs
RUN /home/linuxbrew/.linuxbrew/bin/mkcert -key-file /etc/nginx/certs/soketi-key.pem -cert-file /etc/nginx/certs/soketi.pem soketi
RUN /home/linuxbrew/.linuxbrew/bin/mkcert -key-file /etc/nginx/certs/localhost-key.pem -cert-file /etc/nginx/certs/localhost.pem localhost

# setup nginx as an https reverse proxy
COPY sounding-center/infrastructure/sail/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf
COPY sounding-center/infrastructure/sail/nginx/conf.d/soketi.conf /etc/nginx/conf.d/soketi.conf


#################
## finishing steps ##
#################

# clear apt cache
RUN apt clean && rm -rf /var/lib/apt/lists/*

# if soketi is needed, just run:
# nginx && pm2 start soketi -- start
