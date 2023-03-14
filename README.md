LimeSurvey
==========

LimeSurvey - the most popular
Free Open Source Software survey tool on the web.

https://www.limesurvey.org/en/

This docker image is for Limesurvey on apache/php in its own container. It accepts environment variables to update the configuration file. On first run it will automatically create the database if a username and password are supplied, and on subsequent runs it can update the administrator password if provided as an environment variable.

Volumes are specified for plugins and upload directories for persistence.

# Tags

--    latest - Tracks LimeSurvey latest stable release
--    lts - Tracks LimeSurvey LTS release

Tags corresponding to version on https://community.limesurvey.org/downloads/

# How to use this image

```console
$ docker run --name some-limesurvey --link some-mysql:mysql -d adamzammit/limesurvey
```

The following environment variables are also honored for configuring your Limesurvey instance. If Limesurvey is already installed, these environment variables will update the Limesurvey config file.

-	`-e LIMESURVEY_DB_HOST=...` (defaults to the IP and port of the linked `mysql` container)
-	`-e LIMESURVEY_DB_USER=...` (defaults to "root")
-	`-e LIMESURVEY_DB_PASSWORD=...` (defaults to the value of the `MYSQL_ROOT_PASSWORD` environment variable from the linked `mysql` container)
-	`-e LIMESURVEY_DB_NAME=...` (defaults to "limesurvey")
-	`-e LIMESURVEY_TABLE_PREFIX=...` (defaults to "" - set this to "lime_" for example if your database has a prefix)
-	`-e LIMESURVEY_ADMIN_USER=...` (defaults to "" - the username of the Limesurvey administrator)
-	`-e LIMESURVEY_ADMIN_PASSWORD=...` (defaults to "" - the password of the Limesurvey administrator)
-	`-e LIMESURVEY_ADMIN_NAME=...` (defaults to "Lime Administrator" - The full name of the Limesurvey administrator)
-	`-e LIMESURVEY_ADMIN_EMAIL=...` (defaults to "lime@lime.lime" - The email address of the Limesurvey administrator)
-	`-e LIMESURVEY_DEBUG=...` (defaults to 0 - Debug level of Limesurvey, 0 is off, 1 for errors, 2 for strict PHP and to be able to edit standard templates)
-	`-e LIMESURVEY_SQL_DEBUG=...` (defaults to 0 - Debug level of Limesurvey for SQL, 0 is off, 1 is on - note requires LIMESURVEY_DEBUG set to 2)
-	`-e LIMESURVEY_USE_INNODB=...` (defaults to '' - Leave blank or don't set to use standard MyISAM database. Set to any value to use InnoDB (required for some cloud providers))
-	`-e LIMESURVEY_USE_DB_SESSIONS=...` (defaults to '' - Leave blank or don't set to use file based sessions. Set to any value to use DB based sessions
-	`-e MYSQL_SSL_CA=...` (path to an SSL CA for MySQL based in the root directory (/var/www/html). If changing paths, escape your forward slashes. Do not set or leave blank for a non SSL connection) - SECURITY NOTE: By default this image sets PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT to "false" for compatability reasons
-	`-e TZ=...` Time zone name. If set, will configure PHP and LimeSurvey to use this time zone

If the `LIMESURVEY_DB_NAME` specified does not already exist on the given MySQL server, it will be created automatically upon startup of the `limesurvey` container, provided that the `LIMESURVEY_DB_USER` specified has the necessary permissions to create it.

If you'd like to be able to access the instance from the host without the container's IP, standard port mappings can be used:

```console
$ docker run --name some-limesurvey --link some-mysql:mysql -p 8080:80 -d adamzammit/limesurvey
```

Then, access it via `http://localhost:8080` or `http://host-ip:8080` in a browser.

If you'd like to use an external database instead of a linked `mysql` container, specify the hostname and port with `LIMESURVEY_DB_HOST` along with the password in `LIMESURVEY_DB_PASSWORD` and the username in `LIMESURVEY_DB_USER` (if it is something other than `root`):

```console
$ docker run --name some-limesurvey -e LIMESURVEY_DB_HOST=10.1.2.3:3306 \
    -e LIMESURVEY_DB_USER=... -e LIMESURVEY_DB_PASSWORD=... -d adamzammit/limesurvey
```

## ... via [`docker-compose`](https://github.com/docker/compose)

Example `docker-compose.yml` for `limesurvey`:

```yaml
version: '2'

services:

  limesurvey:
    image: adamzammit/limesurvey
    ports:
      - 8082:80
    environment:
      LIMESURVEY_DB_PASSWORD: example
      LIMESURVEY_ADMIN_USER: admin
      LIMESURVEY_ADMIN_PASSWORD: password
      LIMESURVEY_ADMIN_NAME: Lime Administrator
      LIMESURVEY_ADMIN_EMAIL: lime@lime.lime

  mysql:
    image: mariadb
    environment:
      MYSQL_ROOT_PASSWORD: example
```

Run `docker-compose up`, wait for it to initialize completely, and visit `http://localhost:8082` or `http://host-ip:8082`.

# Supported Docker versions

This image is officially supported on Docker version 1.12.3.

Support for older versions (down to 1.6) is provided on a best-effort basis.

Please see [the Docker installation documentation](https://docs.docker.com/installation/) for details on how to upgrade your Docker daemon.

Notes
-----

This Dockerfile is based on the Dockerfile from the [Wordpress official docker image](https://github.com/docker-library/wordpress/tree/8ab70dd61a996d58c0addf4867a768efe649bf65/php5.6/apache)

