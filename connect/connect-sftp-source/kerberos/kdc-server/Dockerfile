FROM --platform=linux/amd64 debian:bookworm

EXPOSE 749 88/udp

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -qq update && \
    apt-get -qq install locales krb5-kdc krb5-admin-server vim && \
    apt-get -qq clean && rm -rf /var/lib/apt/lists/*

ENV REALM ${REALM:-EXAMPLE.COM}
ENV SUPPORTED_ENCRYPTION_TYPES ${SUPPORTED_ENCRYPTION_TYPES:-aes256-cts-hmac-sha1-96:normal}
ENV KADMIN_PRINCIPAL ${KADMIN_PRINCIPAL:-kadmin/admin}
ENV KADMIN_PASSWORD ${KADMIN_PASSWORD:-adminpassword}

COPY init-script.sh /tmp/
CMD /tmp/init-script.sh
