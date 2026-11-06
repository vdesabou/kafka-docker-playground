ARG DOMAIN_FILE
FROM almalinux:9
ARG DOMAIN_FILE
RUN yum install -y bind
RUN /usr/sbin/rndc-confgen -a -b 512 -k rndc-key
RUN chmod 755 /etc/rndc.key
# named runs as user named: it needs to write to its directory and pid-file folder (named.conf)
RUN mkdir -p /etc/named /run/named && chown named:named /etc/named /run/named

EXPOSE 53/UDP
EXPOSE 53/TCP

COPY named.conf /etc/bind/
COPY ${DOMAIN_FILE} /etc/bind/master/confluent.io

CMD ["/usr/sbin/named", "-c", "/etc/bind/named.conf", "-g", "-u", "named"]