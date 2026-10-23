#!/bin/sh
set -eu

escape_property() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/=/\\=/g' -e 's/:/\\:/g'
}

DB_HOST_ESCAPED=$(escape_property "${DB_HOST:-mysql-db}")
DB_NAME_ESCAPED=$(escape_property "${DB_NAME:-shopping-cart}")
DB_USERNAME_ESCAPED=$(escape_property "${DB_USERNAME:-root}")
DB_PASSWORD_ESCAPED=$(escape_property "${DB_PASSWORD:?DB_PASSWORD must be set}")

cat > /usr/local/tomcat/webapps/ROOT/WEB-INF/classes/application.properties <<EOF
db.driverName = com.mysql.cj.jdbc.Driver
db.connectionString = jdbc:mysql://${DB_HOST_ESCAPED}:3306/${DB_NAME_ESCAPED}?useSSL=false&allowPublicKeyRetrieval=true
db.username = ${DB_USERNAME_ESCAPED}
db.password = ${DB_PASSWORD_ESCAPED}
EOF

exec /usr/local/tomcat/bin/catalina.sh run
