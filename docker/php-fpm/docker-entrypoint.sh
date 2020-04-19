#!/bin/sh
set -e

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
    set -- php-fpm "$@"
fi

if [ "$1" = 'php-fpm' ] || [ "$1" = 'bin/console' ]; then
    mkdir -p storage/logs
	setfacl -R -m u:www-data:rwX -m u:"$(whoami)":rwX storage bootstrap/cache
	setfacl -dR -m u:www-data:rwX -m u:"$(whoami)":rwX storage bootstrap/cache

    if [ "$APP_ENV" != 'prod' ]; then
        composer install --prefer-dist --no-progress --no-suggest --no-interaction
    fi

    if [ "$(ls -A database/migrations/*.php 2> /dev/null)" ]; then
        echo "Migrations..."
        #php artisan migrate --force
    fi

    # Queue worker
    #php artisan queue:work --daemon &

fi

exec docker-php-entrypoint "$@"
