FROM maven:3.9.9-eclipse-temurin-8 AS build

ARG SHOPPING_CART_REVISION=38cf844718a37734beccecb7e7d29643b0a35ce1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN git init /src \
    && git -C /src remote add origin https://github.com/diehardrockstar-star/shoppingcart.git \
    && git -C /src fetch --depth 1 origin "${SHOPPING_CART_REVISION}" \
    && git -C /src checkout --detach FETCH_HEAD

WORKDIR /src
RUN mvn -B -DskipTests clean package \
    && mkdir /src/app \
    && cd /src/app \
    && jar xf /src/target/shopping-cart-0.0.1-snapshot.war

FROM tomcat:9.0-jre8-temurin

RUN rm -rf /usr/local/tomcat/webapps/ROOT
COPY --from=build --chown=10001:0 /src/app/ /usr/local/tomcat/webapps/ROOT/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chown -R 10001:0 /usr/local/tomcat \
    && chmod -R g=u /usr/local/tomcat \
    && chmod 755 /usr/local/bin/docker-entrypoint.sh \
    && chown 10001:0 /usr/local/bin/docker-entrypoint.sh

USER 10001:0
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
