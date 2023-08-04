#!/bin/bash
set -eu

cd /var/www/html

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
	file_env 'LIMESURVEY_DB_HOST' 'mysql'
	file_env 'LIMESURVEY_TABLE_PREFIX' ''
    file_env 'LIMESURVEY_ADMIN_NAME' 'Lime Administrator'
    file_env 'LIMESURVEY_ADMIN_EMAIL' 'lime@lime.lime'
    file_env 'LIMESURVEY_ADMIN_USER' ''
    file_env 'LIMESURVEY_ADMIN_PASSWORD' ''
    file_env 'LIMESURVEY_DEBUG' '0'
    file_env 'LIMESURVEY_SQL_DEBUG' '0'
    file_env 'MYSQL_SSL_CA' ''
    file_env 'LIMESURVEY_USE_INNODB' ''
    file_env 'LIMESURVEY_USE_DB_SESSIONS' ''

	# if we're linked to MySQL and thus have credentials already, let's use them
	file_env 'LIMESURVEY_DB_USER' "${MYSQL_ENV_MYSQL_USER:-root}"
	if [ "$LIMESURVEY_DB_USER" = 'root' ]; then
		file_env 'LIMESURVEY_DB_PASSWORD' "${MYSQL_ENV_MYSQL_ROOT_PASSWORD:-}"
	else
		file_env 'LIMESURVEY_DB_PASSWORD' "${MYSQL_ENV_MYSQL_PASSWORD:-}"
	fi
	file_env 'LIMESURVEY_DB_NAME' "${MYSQL_ENV_MYSQL_DATABASE:-limesurvey}"
	if [ -z "$LIMESURVEY_DB_PASSWORD" ]; then
		echo >&2 'error: missing required LIMESURVEY_DB_PASSWORD environment variable'
		echo >&2 '  Did you forget to -e LIMESURVEY_DB_PASSWORD=... ?'
		echo >&2
		echo >&2 '  (Also of interest might be LIMESURVEY_DB_USER and LIMESURVEY_DB_NAME.)'
		exit 1
	fi

    chmod ug+w -R application/config

    if ! [ -e application/config/config.php ]; then
        echo >&2 "No config file in $(pwd) Copying default config file..."
		#Copy default config file but also allow for the addition of attributes
awk '/lime_/ && c == 0 { c = 1; system("cat") } { print }' application/config/config-sample-mysql.php > application/config/config.php <<'EOPHP'
'attributes' => array(),
EOPHP
    fi

	# Install BaltimoreCyberTrustRoot.crt.pem
	if ! [ -e BaltimoreCyberTrustRoot.crt.pem ]; then
		echo "Downloading BaltimoreCyberTrustroot.crt.pem"
		if curl -o BaltimoreCyberTrustRoot.crt.pem -fsL "https://www.digicert.com/CACerts/BaltimoreCyberTrustRoot.crt.pem"; then
            echo "Downloaded successfully"
        else
            echo "Failed to download certificate - continuing anyway"
        fi
    fi

    # see http://stackoverflow.com/a/2705678/433558
    sed_escape_lhs() {
        echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
    }
    sed_escape_rhs() {
        echo "$@" | sed -e 's/[\/&]/\\&/g'
    }
    php_escape() {
        php -r 'var_export(('$2') $argv[1]);' -- "$1"
    }
    set_config() {
        key="$1"
        value="$2"
        sed -i "/'$key'/s>\(.*\)>$value,1"  application/config/config.php
    }

    set_config 'connectionString' "'mysql:host=$LIMESURVEY_DB_HOST;port=3306;dbname=$LIMESURVEY_DB_NAME;'"
    set_config 'tablePrefix' "'$LIMESURVEY_TABLE_PREFIX'"
    set_config 'username' "'$LIMESURVEY_DB_USER'"
    set_config 'password' "'$LIMESURVEY_DB_PASSWORD'"
	set_config 'urlFormat' "'path'"
    set_config 'debug' "$LIMESURVEY_DEBUG"
    set_config 'debugsql' "$LIMESURVEY_SQL_DEBUG"

	if [ -n "$MYSQL_SSL_CA" ]; then
		set_config 'attributes' "array(PDO::MYSQL_ATTR_SSL_CA => '\/var\/www\/html\/$MYSQL_SSL_CA', PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false)"
    fi

    #Remove session line if exists
    sed -i "/^'session'/d" application/config/config.php

    if [ -n "$LIMESURVEY_USE_DB_SESSIONS" ]; then
        #Add session line
awk '/DbHttpSession/ && c == 0 { c = 1; system("cat") } { print }' application/config/config.php > application/config/config.tmp <<'EOPHP'
'session' => array ('class' => 'application.core.web.DbHttpSession', 'connectionID' => 'db', 'sessionTableName' => '{{sessions}}', 'autoCreateSessionTable' => false, ),
EOPHP
       mv application/config/config.tmp application/config/config.php
    fi


	if [ -n "$LIMESURVEY_USE_INNODB" ]; then
		#If you want to use INNODB - remove MyISAM specification from LimeSurvey code
        chmod ug+w application/core/db/MysqlSchema.php
		sed -i "/ENGINE=MyISAM/s/\(ENGINE=MyISAM \)//1" application/core/db/MysqlSchema.php
        chmod ug-w application/core/db/MysqlSchema.php
    fi

    #Set timezone based on environment to config file if not already there
    grep -qF 'date_default_timezone_set' application/config/config.php || sed --in-place '/^}/a\$longName = exec("echo \\$TZ"); if (!empty($longName)) {date_default_timezone_set($longName);}' application/config/config.php


    chmod ug-w -R application/config
    chmod ug=rwx -R tmp
    chmod ug=rwx -R upload
    chown www-data:www-data -R tmp 
    mkdir -p upload/surveys
    chown www-data:www-data -R upload 
    chown www-data:www-data -R application/config

	DBSTATUS=$(TERM=dumb php -- "$LIMESURVEY_DB_HOST" "$LIMESURVEY_DB_USER" "$LIMESURVEY_DB_PASSWORD" "$LIMESURVEY_DB_NAME" "$LIMESURVEY_TABLE_PREFIX" "$MYSQL_SSL_CA" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

error_reporting(E_ERROR | E_PARSE);

$stderr = fopen('php://stderr', 'w');

list($host, $socket) = explode(':', $argv[1], 2);
$port = 0;
if (is_numeric($socket)) {
        $port = (int) $socket;
        $socket = null;
}

$maxTries = 10;
do {
    $con = mysqli_init();
    if (isset($argv[6]) && !empty($argv[6])) {
	    mysqli_ssl_set($con,NULL,NULL,"/var/www/html/" . $argv[6],NULL,NULL);
    }
    $mysql = mysqli_real_connect($con,$host, $argv[2], $argv[3], '', $port, $socket, MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT);
        if (!$mysql) {
                fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
                --$maxTries;
                if ($maxTries <= 0) {
                        exit(1);
                }
                sleep(3);
        }
} while (!$mysql);

if (!$con->query('CREATE DATABASE IF NOT EXISTS `' . $con->real_escape_string($argv[4]) . '`')) {
        fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $con->error . "\n");
        $con->close();
        exit(1);
}

$con->select_db($con->real_escape_string($argv[4]));

$inst = $con->query("SELECT * FROM `" . $con->real_escape_string($argv[5]) . "users" . "`");

$con->close();

if ($inst->num_rows > 0) {
        exit("DBEXISTS");
} else {
        exit(0);
}

EOPHP
)


	if [ "$DBSTATUS" != "DBEXISTS" ] &&  [ -n "$LIMESURVEY_ADMIN_USER" ] && [ -n "$LIMESURVEY_ADMIN_PASSWORD" ]; then
        echo >&2 'Database not yet populated - installing Limesurvey database'
	    php application/commands/console.php install "$LIMESURVEY_ADMIN_USER" "$LIMESURVEY_ADMIN_PASSWORD" "$LIMESURVEY_ADMIN_NAME" "$LIMESURVEY_ADMIN_EMAIL" verbose
	fi

	if [ -n "$LIMESURVEY_ADMIN_USER" ] && [ -n "$LIMESURVEY_ADMIN_PASSWORD" ]; then
		echo >&2 'Updating password for admin user'
        php application/commands/console.php resetpassword "$LIMESURVEY_ADMIN_USER" "$LIMESURVEY_ADMIN_PASSWORD"
	fi

    if [ -n "$LIMESURVEY_USE_DB_SESSIONS" ]; then
        #Ensure sessions table exists and there is an index on the expire column for performance

        echo >&2 'Ensure sessions table exists and index on expire column for extra performance'
DBSTATUS=$(TERM=dumb php -- "$LIMESURVEY_DB_HOST" "$LIMESURVEY_DB_USER" "$LIMESURVEY_DB_PASSWORD" "$LIMESURVEY_DB_NAME" "$LIMESURVEY_TABLE_PREFIX" "$MYSQL_SSL_CA" <<'EOPHP'
<?php
error_reporting(E_ERROR | E_PARSE);

$stderr = fopen('php://stderr', 'w');

list($host, $socket) = explode(':', $argv[1], 2);
$port = 0;
if (is_numeric($socket)) {
        $port = (int) $socket;
        $socket = null;
}

$maxTries = 10;
do {
    $con = mysqli_init();
    if (isset($argv[6]) && !empty($argv[6])) {
	    mysqli_ssl_set($con,NULL,NULL,"/var/www/html/" . $argv[6],NULL,NULL);
    }
    $mysql = mysqli_real_connect($con,$host, $argv[2], $argv[3], '', $port, $socket, MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT);
        if (!$mysql) {
                fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
                --$maxTries;
                if ($maxTries <= 0) {
                        exit(1);
                }
                sleep(3);
        }
} while (!$mysql);

$con->select_db($con->real_escape_string($argv[4]));

$inst = $con->query("SELECT 1 FROM `" . $con->real_escape_string($argv[5]) . "sessions" . "`");

if ($inst === FALSE) {
    //create table with index
    fwrite($stderr, "No sessions table exists - creating...\n");
    $ntable = $con->query("CREATE TABLE `" . $con->real_escape_string($argv[5]) . "sessions" . "`(`id` varchar(32) NOT NULL, `expire` int(11) DEFAULT NULL, `data` blob, PRIMARY KEY (`id`), KEY(`expire`))");
} else {
    //check index
    fwrite($stderr, "Checking index exists on expire column in sessions table...\n");
    $indx = $con->query("SHOW INDEX FROM `" . $con->real_escape_string($argv[5]) . "sessions" . "` WHERE column_name = 'expire'");
    if ($indx->num_rows == 0) {
        fwrite($stderr, "No index exists on expire column in sessions table - creating...\n");
        $nindx = $con->query("ALTER TABLE `" . $con->real_escape_string($argv[5]) . "sessions" . "` ADD INDEX (expire)");
    } else {
		fwrite($stderr, "Index exists!\n");
	}
}

$con->close();

EOPHP
)
    fi


    #flush asssets (clear cache on restart)
    php application/commands/console.php flushassets
fi

exec "$@"
