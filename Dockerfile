FROM alpine:3.8

MAINTAINER JCSoft <jcsoft@aliyun.com>


ENV fpm_conf /etc/php7/php-fpm.d/www.conf
ENV php_ini /etc/php7/php.ini

# Add repos
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
  apk update && \
  apk upgrade && \
  apk add nginx bash ssmtp git \
  php7 php7-phar php7-curl \
  php7-fpm php7-json php7-zlib php7-xml php7-xmlreader php7-xmlwriter php7-xsl php7-dom php7-ctype php7-opcache php7-zip php7-iconv \
  php7-pdo php7-pdo_mysql php7-mysqli php7-pdo_sqlite php7-pdo_pgsql php7-mbstring php7-session \
  php7-gd php7-mcrypt php7-openssl php7-sockets php7-posix php7-ldap php7-simplexml php7-tokenizer \
  php7-xdebug php7-apcu php7-intl php7-fileinfo php7-imagick php7-gmp \
  curl openssl supervisor && \
  mkdir /etc/nginx/certificates && \
  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/certificates/key.pem \
    -out /etc/nginx/certificates/cert.pem \
    -days 365 \
    -nodes \
    -subj /CN=localhost && \
  rm -rf /var/cache/apk/* && \
  ln -sf /dev/stdout /var/log/nginx/access.log && \
  ln -sf /dev/stderr /var/log/nginx/error.log && \
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer && \
  mkdir -p /etc/nginx && \
  mkdir -p /var/run/php-fpm && \
  mkdir -p /var/log/supervisor && \
  mkdir -p /etc/supervisor/conf.d &&\
  rm -Rf /etc/nginx/nginx.conf && \
  sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 10/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 3/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 200/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf} &&\
  sed -i \
    -e "s/;session.save_path = \"\/tmp\"/session.save_path = \"\/tmp\"/g" \
    ${php_ini}

COPY conf/supervisord.conf /etc/supervisord.conf

# Copy our nginx config

COPY conf/nginx.conf /etc/nginx/nginx.conf

# nginx site conf
RUN mkdir -p /etc/nginx/sites-available/ && \
  mkdir -p /etc/nginx/sites-enabled/ && \
  mkdir -p /etc/nginx/ssl/ && \
  rm -Rf /var/www/* && \
  mkdir /var/www/html/

COPY conf/nginx-site.conf /etc/nginx/sites-available/default.conf
COPY conf/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf
RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

COPY scripts/ /usr/local/bin/
#COPY scripts/pull /usr/local/bin/pull
#COPY scripts/push /usr/bin/push
#COPY scripts/letsencrypt-setup /usr/bin/letsencrypt-setup
#COPY scripts/letsencrypt-renew /usr/bin/letsencrypt-renew
RUN chmod 755 /usr/local/bin/pull && chmod 755 /usr/local/bin/push && chmod 755 /usr/local/bin/letsencrypt-setup && chmod 755 /usr/local/bin/letsencrypt-renew && chmod 755 /usr/local/bin/start.sh

#chmod 755 /usr/bin/pull && chmod 755 /usr/bin/push && 
# copy in code
COPY src/ /var/www/html/
COPY errors/ /var/www/errors

VOLUME ['/var/www/html','/var/log']

EXPOSE 443 80

CMD ["/usr/local/bin/start.sh"]
