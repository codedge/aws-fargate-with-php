# Global settings
ARG PHP_VERSION=7.4
ARG NODE_VERSION=11
ARG NGINX_VERSION=1.17

FROM php:${PHP_VERSION}-fpm-alpine AS laravelapp_php

# persistent / runtime deps
RUN apk add --no-cache \
        acl \
        file \
        gettext \
        git \
        mariadb-client \
    ;

ARG APCU_VERSION=5.1.17
RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        coreutils \
        freetype-dev \
        icu-dev \
        libjpeg-turbo-dev \
        libtool \
        libwebp-dev \
        libzip-dev \
        mariadb-dev \
    ; \
    \
    docker-php-ext-configure gd --with-jpeg=/usr/include/ --with-webp=/usr/include --with-freetype=/usr/include/; \
    docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        intl \
        pdo_mysql \
        zip \
    ; \
    pecl install \
        apcu-${APCU_VERSION} \
    ; \
    pecl clear-cache; \
    docker-php-ext-enable \
        apcu \
        opcache \
    ; \
    \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .laravelapp-phpexts-rundeps $runDeps; \
    \
    apk del .build-deps

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
COPY docker/php-fpm/php.ini /usr/local/etc/php/php.ini
COPY docker/php-fpm/php-cli.ini /usr/local/etc/php/php-cli.ini
COPY docker/php-fpm/zz-docker.conf /usr/local/etc/php-fpm.d/zzz-docker.conf

# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PATH="${PATH}:/root/.composer/vendor/bin"

WORKDIR /srv/laravelapp

# build for production
ARG APP_ENV=production

# copy everything, excluding the one from .dockerignore file
COPY . ./

RUN set -eux; \
    mkdir -p storage/logs storage/framework bootstrap/cache; \
    composer install --prefer-dist --no-progress --no-suggest --optimize-autoloader; \
    composer clear-cache

COPY docker/php-fpm/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]

FROM node:${NODE_VERSION}-alpine AS laravelapp_nodejs

WORKDIR /srv/laravelapp

RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        g++ \
        gcc \
        git \
        make \
        python \
    ;

# prevent the reinstallation of vendors at every changes in the source code
COPY package.json yarn.lock webpack.mix.js ./
COPY resources/ ./resources/
RUN set -eux; \
    yarn install; \
    yarn cache clean;

RUN set -eux; \
	npm run prod

COPY docker/nodejs/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["yarn", "watch"]

# NGINX
FROM nginx:${NGINX_VERSION}-alpine AS laravelapp_nginx

COPY docker/nginx/conf.d/default.conf /etc/nginx/conf.d/

WORKDIR /srv/laravelapp

COPY --from=laravelapp_php /srv/laravelapp/public public/
COPY --from=laravelapp_nodejs /srv/laravelapp/public public/
