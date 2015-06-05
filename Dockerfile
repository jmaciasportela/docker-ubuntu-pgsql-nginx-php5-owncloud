FROM phusion/baseimage:latest
MAINTAINER Jesus Macias <jesus@owncloud.com>
ENV DEBIAN_FRONTEND noninteractive

# Set correct environment variables
ENV HOME /root
# Fix a Debianism of the nobody's uid being 65534
RUN usermod -u 99 nobody
RUN usermod -g 100 nobody

# Activar SSH
RUN rm -fr /etc/service/sshd/down

# Update root password
# CHANGE IT # to something like root:ASdSAdfÑ3
RUN echo "root:root" | chpasswd

# Enable ssh for root
RUN sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
# Enable this option to prevent SSH drop connections
RUN printf "ClientAliveInterval 15\\nClientAliveCountMax 8" >> /etc/ssh/sshd_config

# Add the PostgreSQL PGP key to verify their Debian packages.
# It should be the same key as https://www.postgresql.org/media/keys/ACCC4CF8.asc
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

# Add PostgreSQL's repository. It contains the most recent stable release
#     of PostgreSQL, ``9.3``.
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list

#Setup environment
ENV OC_URL http://download.owncloud.org/community/owncloud-daily-master.tar.bz2
ENV OC_ADMIN_USER admin
ENV OC_ADMIN_PASS Password
ENV DB_REMOTE_ROOT_USER owncloud
ENV DB_REMOTE_ROOT_PASS owncloud

# Push install script
ADD installoc.sh /etc/my_init.d/10_installoc.sh
RUN chmod +x /etc/my_init.d/10_installoc.sh

# Install owncloud dependencies
RUN apt-get update -q && apt-get install -y --force-yes nginx php5-fpm php5-common php5-gd php-xml-parser php5-intl php5-mcrypt php5-curl php5-json php5-ldap php-soap php5-xdebug wget rsync unzip

# Modify php.ini
RUN sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 5000M/g' /etc/php5/fpm/php.ini
RUN sed -i 's/post_max_size = 8M/post_max_size = 5000M/g' /etc/php5/fpm/php.ini
RUN sed -i 's/;default_charset = "UTF-8"/default_charset = "UTF-8"/g' /etc/php5/fpm/php.ini

#Enable Xdebug
# Added for xdebug
RUN printf "xdebug.remote_enable=1\\nxdebug.remote_handler=dbgp\\nxdebug.remote_mode=req\\nxdebug.remote_host=0.0.0.0\\nxdebug.remote_port=9000" >> /etc/php5/mods-available/xdebug.ini

RUN echo "daemon off;" >> /etc/nginx/nginx.conf
RUN sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php5/fpm/php-fpm.conf
RUN sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini

# Install ``python-software-properties``, ``software-properties-common`` and PostgreSQL 9.3
#  There are some warnings (in red) that show up during the build. You can hide
#  them by prefixing each apt-get statement with DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y python-software-properties software-properties-common postgresql-9.3 postgresql-client-9.3 postgresql-contrib-9.3 php5-pgsql phppgadmin

# Note: The official Debian and Ubuntu images automatically ``apt-get clean``
# after each ``apt-get``

# Run the rest of the commands as the ``postgres`` user created by the ``postgres-9.3`` package when it was ``apt-get installed``
USER postgres

# Create a PostgreSQL role named ``docker`` with ``docker`` as the password and
# then create a database `docker` owned by the ``docker`` role.
# Note: here we use ``&&\`` to run commands one after the other - the ``\``
#       allows the RUN command to span multiple lines.
RUN    /etc/init.d/postgresql start &&\
    psql --command "CREATE USER owncloud WITH SUPERUSER PASSWORD 'owncloud';" &&\
    createdb -O owncloud owncloud

USER root

# Generate selfsigned certificate
RUN mkdir /etc/nginx/ssl
RUN printf "ES\\nCYL\\nValladolid\\nOwncloud\\nDocker\\nyour.server.com\\n\\n" | openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -keyout /etc/apache2/ssl/server.key -out /etc/apache2/ssl/server.crt

# Configure nginx to run owncloud
RUN rm /etc/nginx/sites-enabled/default
ADD nginx_owncloud.conf /etc/nginx/sites-enabled/

# Configure nginx service
RUN mkdir /etc/service/nginx
RUN echo '#!/usr/bin/env bash' > /etc/service/nginx/run
RUN echo 'nginx' >> /etc/service/nginx/run && chmod +x /etc/service/nginx/run

RUN mkdir /etc/service/phpfpm
RUN echo '#!/usr/bin/env bash' > /etc/service/phpfpm/run
RUN echo 'php5-fpm -c /etc/php5/fpm' >> /etc/service/phpfpm/run && chmod +x /etc/service/phpfpm/run

# Configure Postgres service
RUN mkdir /etc/service/pgsql
RUN echo '#!/bin/sh' > /etc/service/pgsql/run
RUN echo 'exec /sbin/setuser postgres /usr/lib/postgresql/9.3/bin/postgres -D /var/lib/postgresql/9.3/main -c config_file=/etc/postgresql/9.3/main/postgresql.conf > /dev/null' >> /etc/service/pgsql/run && chmod +x /etc/service/pgsql/run

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Autoconfig owncloud
ADD generate_autoconfig.php /root/generate_autoconfig.php

# Push pgsql reset password on boot
ADD reset_pgsql_pwd.sh /etc/my_init.d/02_reset_pgsql_pwd.sh
RUN chmod +x /etc/my_init.d/02_reset_pgsql_pwd.sh

# Expose port. Cannot be modified!
EXPOSE 22 80 443 8080 9000

# Expose ownCloud's data dir
VOLUME ["/opt/owncloud/data"]

# Use baseimage-docker's init system
CMD ["/sbin/my_init"]
