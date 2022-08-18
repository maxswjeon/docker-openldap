FROM alpine:latest as pqchecker_builder

ARG PQCHECKER_VERSION=2.0.0

RUN apk add --upgrade --no-cache alpine-sdk && apk add --no-cache openldap openldap-dev openjdk11 gettext gettext-dev automake autoconf libtool

RUN git clone --branch v$(cat /etc/alpine-release) --depth 1 git://git.alpinelinux.org/aports
WORKDIR /aports/main/openldap
RUN abuild -F fetch verify && \
    cd src && \
    tar xf openldap-*.tgz && \
    cd $(ls openldap*.tgz | sed 's/\.[^.][^.]*$//') && \
    ./configure && \
    make depend

WORKDIR /
RUN git clone https://bitbucket.org/ameddeb/pqchecker.git && \
    cd pqchecker && \
    git checkout v${PQCHECKER_VERSION}
WORKDIR /pqchecker
RUN ./configure LDAPSRC=$(ls /aports/main/openldap/src/openldap*.tgz | sed 's/\.[^.][^.]*$//') \
                JAVAHOME=/usr/lib/jvm/java-11-openjdk \
                libdir=/usr/lib/openldap \
                PARAMDIR=/etc/openldap/pqchecker \
    && autoreconf -f -i && make && make install


FROM alpine:latest

ARG LDAP_OPENLDAP_GID
ARG LDAP_OPENLDAP_UID

RUN if [ -z "${LDAP_OPENLDAP_GID}"]; then addgroup -g 911 -S openldap; else addgroup -g ${LDAP_OPENLDAP_GID} -S openldap; fi \
    && if [ -z "${LDAP_OPENLDAP_UID}"]; then adduser -u 911 -S -G openldap openldap; else adduser -u ${LDAP_OPENLDAP_UID} -S -G openldap openldap; fi

RUN apk add --no-cache sed openssl \
                       openldap openldap-clients openldap-overlay-all openldap-passwd-argon2 openldap-passwd-pbkdf2 openldap-passwd-sha2 openldap-backend-all \
                       cyrus-sasl cyrus-sasl-crammd5 cyrus-sasl-digestmd5 cyrus-sasl-gs2 cyrus-sasl-gssapiv2 cyrus-sasl-login cyrus-sasl-ntlm cyrus-sasl-scram cyrus-sasl-static \
                       krb5 krb5-conf krb5-server krb5-server-ldap && \
    install -m 755 -o openldap -g openldap -d /certs -d /etc/openldap/slapd.d -d /etc/openldap/pqchecker -d /var/lib/openldap -d /var/lib/openldap/openldap-data -d /var/lib/openldap/run && \
    rm /etc/openldap/slapd.conf

COPY --chown=openldap:openldap ./data/slapd.ldif /etc/openldap/slapd.ldif
COPY --chown=openldap:openldap ./data/pqchecker/* /etc/openldap/pqchecker/
COPY --chown=openldap:openldap --from=pqchecker_builder /usr/lib/openldap/pqchecker* /usr/lib/openldap/
COPY --chown=openldap:openldap ./assets/config /config
COPY --chown=openldap:openldap ./assets/schema-to-ldif.sh /schema-to-ldif.sh
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]

