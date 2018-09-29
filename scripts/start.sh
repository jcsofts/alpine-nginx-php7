#!/bin/bash

# Disable Strict Host checking for non interactive git clones

mkdir -p -m 0700 /root/.ssh
# Prevent config files from being filled to infinity by force of stop and restart the container 
echo "" > /root/.ssh/config
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [[ "$GIT_USE_SSH" == "1" ]] ; then
  echo -e "Host *\n\tUser ${GIT_USERNAME}\n\n" >> /root/.ssh/config
fi

if [ ! -z "$SSH_KEY" ]; then
 echo $SSH_KEY > /root/.ssh/id_rsa.base64
 base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
 chmod 600 /root/.ssh/id_rsa
fi

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
 sed -i "s#root /var/www/html;#root ${WEBROOT};#g" /etc/nginx/sites-available/default.conf
else
 webroot=/var/www/html
fi

#if [ ! -z "$DOMAIN" ]; then
# sed -i "s#server_name _;#server_name ${DOMAIN};#g" /etc/nginx/sites-available/default.conf
# sed -i "s#server_name _;#server_name ${DOMAIN};#g" /etc/nginx/sites-available/default-ssl.conf
#fi

# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
 git config --global user.email "$GIT_EMAIL"
fi
if [ ! -z "$GIT_NAME" ]; then
 git config --global user.name "$GIT_NAME"
 git config --global push.default simple
fi

# Dont pull code down if the .git folder exists
if [ ! -d "/var/www/html/.git" ]; then
 # Pull down code from git for our site!
 if [ ! -z "$GIT_REPO" ]; then
   # Remove the test index file if you are pulling in a git repo
   if [ ! -z ${REMOVE_FILES} ] && [ ${REMOVE_FILES} == 0 ]; then
     echo "skiping removal of files"
   else
     rm -Rf /var/www/html/*
   fi
   GIT_COMMAND='git clone '
   if [ ! -z "$GIT_BRANCH" ]; then
     GIT_COMMAND=${GIT_COMMAND}" -b ${GIT_BRANCH}"
   fi

   if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
     GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
   else
    if [ "$GIT_USE_SSH" == "1" ]; then
      GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
    else
      GIT_COMMAND=${GIT_COMMAND}" https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO}"
    fi
   fi
   ${GIT_COMMAND} /var/www/html || exit 1
   if [ -z "$SKIP_CHOWN" ]; then
     chown -Rf nginx.nginx /var/www/html
   fi
 fi
fi

# Enable custom nginx config files if they exist
if [ -f /var/www/html/conf/nginx/nginx.conf ]; then
  cp /var/www/html/conf/nginx/nginx.conf /etc/nginx/nginx.conf
fi

if [ -f /var/www/html/conf/nginx/nginx-site.conf ]; then
  cp /var/www/html/conf/nginx/nginx-site.conf /etc/nginx/sites-available/default.conf
fi

if [ -f /var/www/html/conf/nginx/nginx-site-ssl.conf ]; then
  cp /var/www/html/conf/nginx/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf
fi


# Prevent config files from being filled to infinity by force of stop and restart the container
#lastlinephpconf="$(grep "." /usr/local/etc/php-fpm.conf | tail -1)"
#if [[ $lastlinephpconf == *"php_flag[display_errors]"* ]]; then
# sed -i '$ d' /usr/local/etc/php-fpm.conf
#fi

# Display PHP error's or not
if [ "$ERRORS" != "1" ] ; then
  sed -i "s/;php_flag\[display_errors\] = off/php_flag[display_errors] = off/g" /etc/php7/php-fpm.d/www.conf
else
 sed -i "s/;php_flag\[display_errors\] = off/php_flag[display_errors] = on/g" /etc/php7/php-fpm.d/www.conf
 sed -i "s/display_errors = Off/display_errors = On/g" /etc/php7/php.ini
 if [ ! -z "$ERROR_REPORTING" ]; then sed -i "s/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = $ERROR_REPORTING/g" /etc/php7/php.ini; fi
 sed -i "s#;error_log = syslog#error_log = /var/log/php/error.log#g" /etc/php7/php.ini
fi

# Display Version Details or not
if [ "$HIDE_NGINX_HEADERS" == "0" ] ; then
 sed -i "s/server_tokens off;/server_tokens on;/g" /etc/nginx/nginx.conf
else
 sed -i "s/expose_php = On/expose_php = Off/g" /etc/php7/php.ini
fi

# Pass real-ip to logs when behind ELB, etc
if [ "$REAL_IP_HEADER" == "1" ] ; then
 sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/sites-available/default.conf
 sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/sites-available/default.conf
 if [ ! -z "$REAL_IP_FROM" ]; then
  sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/sites-available/default.conf
 fi
fi
# Do the same for SSL sites
if [ -f /etc/nginx/sites-available/default-ssl.conf ]; then
 if [ "$REAL_IP_HEADER" == "1" ] ; then
  sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/sites-available/default-ssl.conf
  sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/sites-available/default-ssl.conf
  if [ ! -z "$REAL_IP_FROM" ]; then
   sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/sites-available/default-ssl.conf
  fi
 fi
fi

# Increase the memory_limit
if [ ! -z "$PHP_MEM_LIMIT" ]; then
 sed -i "s/memory_limit = 128M/memory_limit = ${PHP_MEM_LIMIT}M/g" /etc/php7/php.ini
fi

# Increase the post_max_size
if [ ! -z "$PHP_POST_MAX_SIZE" ]; then
 sed -i "s/post_max_size = 8M/post_max_size = ${PHP_POST_MAX_SIZE}M/g" /etc/php7/php.ini
fi

# Increase the upload_max_filesize
if [ ! -z "$PHP_UPLOAD_MAX_FILESIZE" ]; then
 sed -i "s/upload_max_filesize = 2M/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}M/g" /etc/php7/php.ini
fi

# Increase the max_execution_time
if [ ! -z "$PHP_MAX_EXECUTION_TIME" ]; then
 sed -i "s/max_execution_time = 30/max_execution_time = ${PHP_MAX_EXECUTION_TIME}/g" /etc/php7/php.ini
fi

# Enable xdebug
XdebugFile='/etc/php7/conf.d/xdebug.ini'
if [ "$ENABLE_XDEBUG" == "1" ] ; then
  echo "Enabling xdebug"
    # See if file contains xdebug text.
    if [ -f $XdebugFile ]; then
        echo "Xdebug already enabled... skipping"
    else
      sed -i "s/;zend_extension=xdebug.so/zend_extension=xdebug.so/g" $XdebugFile
      echo "xdebug.remote_enable=1 "  >> $XdebugFile
      echo "xdebug.remote_log=/tmp/xdebug.log"  >> $XdebugFile
      echo "xdebug.remote_autostart=false "  >> $XdebugFile # I use the xdebug chrome extension instead of using autostart
      # echo "xdebug.remote_host=localhost "  >> $XdebugFile
      # echo "xdebug.remote_port=9000 "  >> $XdebugFile
      # NOTE: xdebug.remote_host is not needed here if you set an environment variable in docker-compose like so `- XDEBUG_CONFIG=remote_host=192.168.111.27`.
      #       you also need to set an env var `- PHP_IDE_CONFIG=serverName=docker`
    fi
else
  rm -rf $XdebugFile
fi

if [ ! -z "$PUID" ]; then
  if [ -z "$PGID" ]; then
    PGID=${PUID}
  fi
  #deluser nginx
  addgroup -g ${PGID} nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
else
  if [ -z "$SKIP_CHOWN" ]; then
    chown -Rf nginx.nginx /var/www/html
  fi
fi

# Run custom scripts
if [ "$RUN_SCRIPTS" == "1" ] ; then
  if [ -d "/var/www/html/scripts/" ]; then
    # make scripts executable incase they aren't
    chmod -Rf 750 /var/www/html/scripts/*
    # run scripts in number order
    for i in `ls /var/www/html/scripts/`; do /var/www/html/scripts/$i ; done
  else
    echo "Can't find script directory"
  fi
fi

# Try auto install for composer
#if [ -f "/var/www/html/composer.lock" ]; then
#    if [ "$APPLICATION_ENV" == "development" ]; then
#        composer global require hirak/prestissimo
#        composer install --working-dir=/var/www/html
#    else
#        composer global require hirak/prestissimo
#        composer install --no-dev --working-dir=/var/www/html
#    fi
#fi

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf