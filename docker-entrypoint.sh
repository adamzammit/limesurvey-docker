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
    file_env 'LIMESURVEY_DONT_SHOW_SCRIPT_NAME' ''

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

    echo >&2 "Copying default container default config files into config volume..."
    cp -dR /var/lime/application/config/* application/config

    if ! [ -e plugins/index.html ]; then
        echo >&2 "No index.html file in plugins dir in $(pwd) Copying defaults..."
        cp -dR /var/lime/plugins/* plugins
    fi

    if ! [ -e upload/index.html ]; then
        echo >&2 "No index.html file upload dir in $(pwd) Copying defaults..."
        cp -dR /var/lime/upload/* upload
    fi

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
    set_config 'showScriptName' "true"
    if [ -n "$LIMESURVEY_DONT_SHOW_SCRIPT_NAME" ]; then
        set_config 'showScriptName' "false"
    fi

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
		sed -i "/ENGINE=MyISAM/s/\(ENGINE=MyISAM \)//1" application/core/db/MysqlSchema.php
        #Also set mysqlEngine in config file
		sed -i "/\/\/ Update default LimeSurvey config here/s//'mysqlEngine'=>'InnoDB',/" application/config/config.php
		DBENGINE='InnoDB'
    fi

    #Set timezone based on environment to config file if not already there
    grep -qF 'date_default_timezone_set' application/config/config.php || sed --in-place '/^}/a\$longName = exec("echo \\$TZ"); if (!empty($longName)) {date_default_timezone_set($longName);}' application/config/config.php
    chown www-data:www-data -R tmp 
    chown www-data:www-data -R plugins
    mkdir -p upload/surveys
    chown www-data:www-data -R upload 
    chown www-data:www-data -R application/config
    mkdir -p /var/lime/sessions
    chown www-data:www-data -R /var/lime/sessions

	DBSTATUS=$(TERM=dumb php -- "$LIMESURVEY_DB_HOST" "$LIMESURVEY_DB_USER" "$LIMESURVEY_DB_PASSWORD" "$LIMESURVEY_DB_NAME" "$LIMESURVEY_TABLE_PREFIX" "$MYSQL_SSL_CA" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

error_reporting(E_ERROR | E_PARSE);
mysqli_report(MYSQLI_REPORT_OFF);

$stderr = fopen('php://stderr', 'w');
$host = $argv[1];
$socket = null;
if (str_contains($host, ':')) {
    list($host, $socket) = explode(':', $argv[1], 2);
}
$port = 0;
if (is_numeric($socket)) {
    $port = (int) $socket;
    $socket = null;
}

do {
    $con = mysqli_init();
    if (isset($argv[6]) && !empty($argv[6])) {
	    mysqli_ssl_set($con,NULL,NULL,"/var/www/html/" . $argv[6],NULL,NULL);
    }
    $mysql = mysqli_real_connect($con,$host, $argv[2], $argv[3], '', $port, $socket, MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT);
        if (!$mysql) {
                fwrite($stderr, "MySQL Connection Error will retry in 3 seconds...\n");
                sleep(3);
        }
} while (!$mysql);

if (!$con->query('CREATE DATABASE IF NOT EXISTS `' . $con->real_escape_string($argv[4]) . '`')) {
        fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $con->error . "\n");
        $con->close();
        exit(1);
}

$stat = $con->select_db($con->real_escape_string($argv[4]));

$inst = $con->query("SHOW TABLES LIKE '" . $con->real_escape_string($argv[5]) . "users'");

$nrows = $inst->num_rows;

$con->close();

if ($nrows > 0) {
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

    #flush asssets (clear cache on restart)
    php application/commands/console.php flushassets

fi

exec "$@"
