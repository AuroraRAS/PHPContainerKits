#!/bin/bash

function cmdhelp
{
cat << EOF
# we have some commands maybe can help you

# remove the default website
rm sysroot/etc/nginx/conf.d/default.conf

# remove the example website
rm sysroot/etc/nginx/conf.d/www.example.com.conf

# startup all services
docker-compose up -d

# install dependencies if you need
docker exec -it [yourprojectname]_phpfpm_1 apt update
docker exec -it [yourprojectname]_phpfpm_1 apt install unzip libzip-dev libpng-dev -y

# config php exts before install them
docker exec -it [yourprojectname]_phpfpm_1 docker-php-ext-configure --help
docker exec -it [yourprojectname]_phpfpm_1 docker-php-ext-configure gd --with-jpeg-dir=/usr/local/something

# install php exts
docker exec -it [yourprojectname]_phpfpm_1 docker-php-ext-install --help
docker exec -it [yourprojectname]_phpfpm_1 docker-php-ext-install gd

# stop all services
docker-compose stop

# start all services
docker-compose start

# teardown all services
docker-compose down
EOF
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cmdhelp
    exit 0
fi

if [ "$1" = "-u" ] || [ "$1" = "--update" ]; then
    docker pull "php:fpm" "mariadb:latest" "nginx:latest"
fi

sudo rm -rf "$(pwd)/sysroot/"

mkdir -p "$(pwd)/sysroot/etc"
mkdir -p "$(pwd)/sysroot/etc/letsencrypt"
mkdir -p "$(pwd)/sysroot/usr/bin"
mkdir -p "$(pwd)/sysroot/usr/lib/nginx"
mkdir -p "$(pwd)/sysroot/usr/local"
mkdir -p "$(pwd)/sysroot/usr/share"
mkdir -p "$(pwd)/sysroot/var/lib"
mkdir -p "$(pwd)/sysroot/var/log/nginx"

cp_db=$(docker create --rm mariadb:latest)
docker cp $cp_db:/etc/mysql $(pwd)/sysroot/etc/mysql
docker cp $cp_db:/var/lib/mysql $(pwd)/sysroot/var/lib/mysql
docker rm $cp_db

cp_php=$(docker create --rm php:fpm)
docker cp $cp_php:/usr/local/etc $(pwd)/sysroot/usr/local/etc
docker cp $cp_php:/usr/local/lib $(pwd)/sysroot/usr/local/lib
docker rm $cp_php
cp scripts/laravel-setup.sh $(pwd)/sysroot/usr/bin

cp_web=$(docker create --rm nginx:latest)
docker cp $cp_web:/etc/nginx $(pwd)/sysroot/etc/nginx
docker cp $cp_web:/usr/share/nginx $(pwd)/sysroot/usr/share/nginx
docker cp $cp_web:/usr/lib/nginx/modules $(pwd)/sysroot/usr/lib/nginx/modules
docker rm $cp_web

# copy websites to our working directory
websites=($(ls "websites/"))
for ((i=0; i<${#websites[@]}; i++))
do
    cp -r "$(pwd)/websites/${websites[i]}" "$(pwd)/sysroot/usr/share/nginx/"
    cat "$(pwd)/localhost.conf" | sed "s/localhost/${websites[i]}/" > "$(pwd)/sysroot/etc/nginx/conf.d/${websites[i]}.conf"
done

# usually, we don't need to separating the UIDs for php-fpm and nginx
sed -i "s/user  nginx;/user  www-data;/g" "$(pwd)/sysroot/etc/nginx/nginx.conf"

# make SELinux happy
chcon -Rt svirt_sandbox_file_t "$(pwd)/sysroot"

# change websites owner to www-data
docker run --rm -v "$(pwd)/sysroot/usr/share/nginx:/usr/share/nginx:rw" php:fpm "chown" "-R" "www-data:www-data" "/usr/share/nginx"

cmdhelp
