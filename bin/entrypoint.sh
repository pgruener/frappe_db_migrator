#!/bin/sh

env >> /etc/environment

# run local mysqld
mysql_install_db --user=mysql --ldata=/var/lib/mysql > /dev/null
/usr/bin/mysqld_safe --user=mysql --console --skip-name-resolve --skip-networking=0 &

echo "Waiting for mysqld to start ..."
while ! mysqladmin ping --silent; do
  sleep 1
done

`mysql -e "CREATE USER 'root'@'%';"`
`mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"`
`mysql -e "FLUSH PRIVILEGES;"`

# update crontab
echo "Updating crontab ..."
/app/bin/update_cron.rb

# run immediately ones
RUN_IMMEDIATELY_ONES=true /app/bin/run_targets.rb

# start cron in the foreground (replacing the current process)
echo "Starting ..."
echo "$ $@"
exec "$@"
