#!/bin/bash
# Starts everything inside the container:
# MariaDB, GuardServer on 8081, ShopServer (Abhay's project) on 8082, nginx on $PORT.
set -euo pipefail

DATA=/var/lib/mysql
SOCK=/run/mysqld/mysqld.sock
PORT="${PORT:-8080}"
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

# first run: create the mysql data folder
if [ ! -d "$DATA/mysql" ]; then
  echo "Creating database folder..."
  mariadb-install-db --user=mysql --datadir="$DATA" --skip-test-db >/dev/null
fi

mariadbd --user=mysql --datadir="$DATA" --socket="$SOCK" \
  --innodb-buffer-pool-size="${DB_BUFFER_POOL_SIZE:-24M}" &
DB=$!

# wait for the database (max 90 s)
for _ in $(seq 1 90); do
  if mariadb-admin --socket="$SOCK" ping --silent 2>/dev/null; then break; fi
  if ! kill -0 "$DB" 2>/dev/null; then echo "mariadbd stopped" >&2; exit 1; fi
  sleep 1
done
mariadb-admin --socket="$SOCK" ping --silent || { echo "database did not start" >&2; exit 1; }

# load a schema file only once and make its user
# load_db <name> <sql file> <database> <user> <password>
load_db() {
  local done_file="$DATA/.$1_loaded"
  if [ ! -f "$done_file" ]; then
    echo "Loading $2 ..."
    mariadb --socket="$SOCK" -uroot < "$2"
    mariadb --socket="$SOCK" -uroot <<SQL
CREATE USER IF NOT EXISTS '$4'@'localhost' IDENTIFIED BY '$5';
CREATE USER IF NOT EXISTS '$4'@'127.0.0.1' IDENTIFIED BY '$5';
GRANT ALL PRIVILEGES ON $3.* TO '$4'@'localhost';
GRANT ALL PRIVILEGES ON $3.* TO '$4'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
    touch "$done_file"
  fi
}
load_db fraud  /app/database/guard_schema.sql       fraud_management "$FRAUD_DB_USER" "$FRAUD_DB_PASS"
load_db orders /app/orders/warehouse/shop_schema.sql order_management "$ORDER_DB_USER" "$ORDER_DB_PASS"

(cd /app && PORT=8081 exec java -cp ".:jdbc_driver/*" GuardServer) &
FRAUD=$!
(cd /app/orders && PORT=8082 exec java -cp ".:/app/jdbc_driver/*" ShopServer) &
ORDERS=$!

# open the public port only after both servers are up
for _ in $(seq 1 120); do
  kill -0 "$FRAUD" 2>/dev/null || { echo "GuardServer stopped" >&2; exit 1; }
  kill -0 "$ORDERS" 2>/dev/null || { echo "ShopServer stopped" >&2; exit 1; }
  if (exec 3<>/dev/tcp/127.0.0.1/8081) 2>/dev/null && (exec 3<>/dev/tcp/127.0.0.1/8082) 2>/dev/null; then break; fi
  sleep 1
done

sed "s/PORT_HERE/${PORT}/" /etc/nginx/router.conf > /tmp/nginx.conf
nginx -t -c /tmp/nginx.conf -q
nginx -c /tmp/nginx.conf -g 'daemon off;' &
WEB=$!
echo "Open http://localhost:$PORT  (/orders/ for the shop project)"

trap 'kill "$FRAUD" "$ORDERS" "$WEB" "$DB" 2>/dev/null || true' TERM INT
# if any one of them stops, stop the container too so Render restarts it
set +e
wait -n "$DB" "$FRAUD" "$ORDERS" "$WEB"
code=$?
echo "a process stopped (exit $code), shutting down" >&2
kill "$FRAUD" "$ORDERS" "$WEB" "$DB" 2>/dev/null
[ "$code" -eq 0 ] && code=1
exit "$code"
