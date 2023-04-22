# frappe_db_migrator
Downloads Backup from frappe, and imports it into a remote PostgreSQL DB

Frappe(cloud) typically acts on mariadb and the backups are persisted as those.

With this container, you can schedule (or just run once), data
loads, which grab the data from your frappe account and imports it into a remote PostgreSQL DB of your choice.

It's also possible to reduce the data, if several tables (or doctypes) are not needed in the destination db.

We use that migration for further data analysis & intelligence, which better operates on postgres.

## conf/targets.yml

All targets are configured within this file. Just have a look at the basic provided one.

### Customize with own config

You can inject your own config somewhere (via docker mount/bind) and set the path into the environment variable `CONFIG_FILE`, which will then be used instead of the default targets.yml

Of course you can also overwrite the targets.yml via mount/bind or build an own image with your own config ;-)

#### Targets

##### Target Driver: mysql_to_postgres

```yaml
target_ident:
  source:
    ...
  target:
    type: mysql_to_postgres
    host: PG_HOST # default: localhost
    # port: default: PG_PORT & 5432
    database: PG_DB_NAME
    username: PG_USERNAME
    password: PG_PASSWORD
    overwrite: PG_OVERWRITE # default: false

```

Param details:

| Config Property | Description |
| --------------- | ----------- |
| host | is the host where the postgres db is located to be used |
| database | The DB Name which should be used to import the value to |
| username | Username to login |
| password | Password to Login |
| overwrite | *Default: false* By default the import is not done, if any table is known in the target db. If you set *overwrite: true* the WHOLE! databases tables will be removed before import. WARNING: Really ALL tables are removed in this case, not only the ones, which will be imported.|


...

### Credentials

We provide 3 options of providing required credentials:

1.
Put the credentials into a local .env file (copy .env.example)
Just provide the name of the ENV variable in the corresponding config settings.
The runtime will then check the local .env file for your variable and take it if available. If not it continues with 2.

2.
Publish the credentials as ENV Variables to the running container.
Just provide the name of the ENV variable in the corresponding config settings.
If there is no variable with the same name known in your .env file, the runtime will grab the value of the defined environment variable.

3.
Use docker secrets. In this case just provide the /var/run/secrets/xyz path as the password, instead of the variable name.
