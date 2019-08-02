# -- CLONE the latest javaps and iohandler
FROM alpine/git as CLONE
WORKDIR /usr/src
RUN echo "invalidate the cache with another echo strings3"
RUN git clone https://github.com/52north/javaPS.git app \
    && git clone https://github.com/52North/javaps-iohandler.git app/javaps-iohandler \
    && git clone https://github.com/matthesrieke/javaps-rest.git app/javaps-rest \
    && git clone https://github.com/52North/eopad-javaps-backend.git app/eopad-javaps-backend \
	&& git -C ./app/javaps-iohandler checkout develop \
	&& git -C ./app/javaps-rest checkout master \
  && git -C ./app/eopad-javaps-backend checkout master \
  && git -C ./app checkout tb15/eopad
	
# -- BUILD all components
FROM maven:3.5-jdk-8-alpine as BUILD 
WORKDIR /usr/src/app
COPY --from=CLONE /usr/src/app /usr/src/app
COPY ./javaps/javaps-pom.xml /usr/src/app/pom.xml
RUN mvn -f ./pom.xml clean install -DskipTests -pl !webapp
RUN mvn -f ./javaps-iohandler/pom.xml clean install
RUN mvn -f ./javaps-rest/pom.xml clean install
RUN mvn -f ./eopad-javaps-backend/pom.xml clean install
COPY ./javaps/webapp-pom.xml /usr/src/app/webapp/pom.xml
RUN mvn -f ./pom.xml install -DskipTests

# -- RUNNABLE image based on jetty
FROM jetty:jre8

ARG JAVAPS_VERSION=1.4.0-SNAPSHOT
ENV JAVAPS_VERSION ${JAVAPS_VERSION}
ENV JAVAPS_ROOT ${JETTY_BASE}/webapps/ROOT
ENV JAVAPS_TMP ${JAVAPS_ROOT}/WEB-INF/tmp
ENV JAVAPS_CONFIG ${JAVAPS_ROOT}/WEB-INF/config
ENV JAVAPS_LIB ${JAVAPS_ROOT}/WEB-INF/lib

COPY --from=BUILD /usr/src/app/webapp/target/javaPS-webapp-${JAVAPS_VERSION}/ /var/lib/jetty/webapps/ROOT
COPY etc/docker-log4j2.xml /var/lib/jetty/webapps/ROOT/WEB-INF/config/log4j2.xml
COPY etc/docker-configuration.json /var/lib/jetty/webapps/ROOT/WEB-INF/config/configuration.json
COPY etc/iceland.xml /var/lib/jetty/webapps/ROOT/WEB-INF/classes/components/iceland.xml

USER root
RUN set -ex \
 && apt-get update \
 && apt-get install -y --no-install-recommends jq \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q -P /usr/local/bin https://raw.githubusercontent.com/52North/arctic-sea/master/etc/faroe-entrypoint.sh \
 && chmod +x /usr/local/bin/faroe-entrypoint.sh \
 && ln -sf ${JAVAPS_CONFIG}/log4j2.xml ${JAVAPS_ROOT}/WEB-INF/classes/log4j2.xml \
 && mkdir -p ${JAVAPS_TMP}\
 && chown -R jetty:jetty ${JAVAPS_ROOT}

COPY ./faroe-entrypoint.sh /usr/local/bin/faroe-entrypoint.sh
RUN chmod +x /usr/local/bin/faroe-entrypoint.sh

USER jetty

VOLUME /var/lib/jetty/webapps/ROOT/WEB-INF/tmp
VOLUME /var/lib/jetty/webapps/ROOT/WEB-INF/config

HEALTHCHECK --interval=5s --timeout=20s --retries=3 \
  CMD wget 'http://localhost:8080/service?service=WPS&request=GetCapabilities' -q -O - > /dev/null 2>&1

ENV FAROE_CONFIGURATION ${JAVAPS_CONFIG}/configuration.json

LABEL maintainer="Benjamin Proß <b.pross@52north.org>" \
      org.opencontainers.image.title="52°North javaPS" \
      org.opencontainers.image.description="Next generation standardized web-based geo-processing" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.url="https://github.com/52North/javaPS" \
      org.opencontainers.image.vendor="52°North GmbH" \
      org.opencontainers.image.source="https://github.com/52north/javaPS.git" \
      org.opencontainers.image.documentation="https://github.com/52North/javaPS/blob/develop/README.md" \
      org.opencontainers.image.version="${JAVAPS_VERSION}" \
      org.opencontainers.image.authors="Benjamin Proß <b.pross@52north.org>, Christian Autermann <c.autermann@52north.org>"

ARG GIT_COMMIT
LABEL org.opencontainers.image.revision "${GIT_COMMIT}"

ARG BUILD_DATE
LABEL org.opencontainers.image.created "${BUILD_DATE}"

CMD [ "java", "-jar", "/usr/local/jetty/start.jar" ]
ENTRYPOINT [ "/usr/local/bin/faroe-entrypoint.sh", "/docker-entrypoint.sh" ]
