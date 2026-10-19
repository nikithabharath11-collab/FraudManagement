# Fraud Management System - Docker image for Render
# step 1: compile the java files with the MySQL connector
FROM eclipse-temurin:21-jdk-noble AS build
ARG CONNECTOR_VERSION=9.1.0
WORKDIR /app
COPY . .
RUN mkdir -p jdbc_driver && curl -fsSL -o jdbc_driver/mysql-connector-j-${CONNECTOR_VERSION}.jar \
      https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${CONNECTOR_VERSION}/mysql-connector-j-${CONNECTOR_VERSION}.jar \
 && javac -cp "jdbc_driver/*" GuardServer.java GuardConsole.java \
 && cd orders && javac -cp "../jdbc_driver/*" ShopServer.java ShopConsole.java

# step 2: java runtime + MariaDB (works like MySQL) + nginx
FROM eclipse-temurin:21-jre-noble
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mariadb-server nginx \
 && rm -rf /var/lib/apt/lists/* /var/lib/mysql/*
COPY hosting/mariadb_small.cnf /etc/mysql/mariadb.conf.d/99-guard.cnf
COPY hosting/router.conf /etc/nginx/router.conf
WORKDIR /app
COPY --from=build /app/*.class /app/
COPY --from=build /app/jdbc_driver /app/jdbc_driver
COPY dashboard /app/dashboard
COPY database /app/database
# Abhay's shop project runs in the same container under /orders/
COPY --from=build /app/orders/*.class /app/orders/
COPY orders/storefront /app/orders/storefront
COPY orders/warehouse /app/orders/warehouse
COPY hosting/launch.sh /launch.sh
RUN chmod +x /launch.sh
# defaults, Render overrides the passwords
ENV PORT=8080 \
    FRAUD_DB_URL=jdbc:mysql://127.0.0.1:3306/fraud_management \
    FRAUD_DB_USER=fraud_app \
    FRAUD_DB_PASS=fraud_app_pw \
    ORDER_DB_URL=jdbc:mysql://127.0.0.1:3306/order_management \
    ORDER_DB_USER=order_app \
    ORDER_DB_PASS=order_app_pw \
    DB_BUFFER_POOL_SIZE=24M \
    JAVA_TOOL_OPTIONS="-Xmx96m -XX:+UseSerialGC -XX:MaxMetaspaceSize=64m -Xss512k -XX:TieredStopAtLevel=1"
EXPOSE 8080
ENTRYPOINT ["/launch.sh"]
