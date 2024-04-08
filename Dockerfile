FROM php:8.1-apache

ENV DOWNLOAD_URL https://download.limesurvey.org/latest-master/limesurvey6.5.2+240402.zip
ENV DOWNLOAD_SHA256 bec5c962e35c4e9e5b01cd33cee828fe514b1aa4c00aa01efc3151aaf9322b15

# install the PHP extensions we need
RUN apt-get update && apt-get install -y unzip libc-client-dev libfreetype6-dev libmcrypt-dev libpng-dev libjpeg-dev libldap-common libldap2-dev zlib1g-dev libkrb5-dev libtidy-dev libzip-dev libsodium-dev libpq-dev libonig-dev netcat-openbsd && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-freetype=/usr/include/  --with-jpeg=/usr \
    && docker-php-ext-install gd mysqli mbstring pgsql pdo pdo_mysql pdo_pgsql opcache zip iconv tidy \
    && docker-php-ext-configure ldap --with-libdir=lib/$(gcc -dumpmachine)/ \
    && docker-php-ext-install ldap \
    && docker-php-ext-configure imap --with-imap-ssl --with-kerberos \
    && docker-php-ext-install imap \
    && docker-php-ext-install sodium \
    && pecl install mcrypt-1.0.6 \
    && docker-php-ext-enable mcrypt \
    && docker-php-ext-install exif

RUN a2enmod rewrite

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=2'; \
        echo 'opcache.fast_shutdown=1'; \
        echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN set -x; \
    curl -SL "$DOWNLOAD_URL" -o /tmp/lime.zip; \
    echo "$DOWNLOAD_SHA256 /tmp/lime.zip" | sha256sum -c - || exit 1; \
    unzip /tmp/lime.zip -d /tmp; \
    mv /tmp/lime*/* /var/www/html/; \
    mv /tmp/lime*/.[a-zA-Z]* /var/www/html/; \
    rm /tmp/lime.zip; \
    rmdir /tmp/lime*; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R ug=rx /var/www/html; \
    mkdir -p /var/lime/application/config; \
    mkdir -p /var/lime/upload; \
    mkdir -p /var/lime/plugins; \
    mkdir -p /var/lime/sessions; \
    chown -R www-data:www-data /var/lime/sessions; \
    cp -dpR /var/www/html/application/config/* /var/lime/application/config; \
    cp -dpR /var/www/html/upload/* /var/lime/upload; \
    cp -dpR /var/www/html/plugins/* /var/lime/plugins; \
    chown -R www-data:www-data /var/lime/application; \
    chown -R www-data:www-data /var/lime/plugins; \
    chown -R www-data:www-data /var/lime/upload

#Set PHP defaults for Limesurvey (allow bigger uploads)
RUN { \
        echo 'memory_limit=256M'; \
        echo 'upload_max_filesize=128M'; \
        echo 'post_max_size=128M'; \
        echo 'max_execution_time=120'; \
        echo 'max_input_vars=10000'; \
        echo 'date.timezone=UTC'; \
        echo 'session.gc_maxlifetime=86400'; \
        echo 'session.save_path="/var/lime/sessions"'; \
    } > /usr/local/etc/php/conf.d/limesurvey.ini

VOLUME ["/var/www/html/plugins"]
VOLUME ["/var/www/html/upload"]
VOLUME ["/var/lime/sessions"]

#ensure that the config is persisted especially for security.php
VOLUME ["/var/www/html/application/config"]


COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat

# ENTRYPOINT resets CMD
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
