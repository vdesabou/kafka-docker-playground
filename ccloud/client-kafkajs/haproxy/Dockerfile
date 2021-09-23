FROM haproxy:2.2.5

ENV HAPROXY_USER haproxy

RUN groupadd --system ${HAPROXY_USER} ; \
  useradd --system --gid ${HAPROXY_USER} ${HAPROXY_USER} ; \
  mkdir --parents /var/lib/${HAPROXY_USER} ; \
  chown -R ${HAPROXY_USER}:${HAPROXY_USER} /var/lib/${HAPROXY_USER} || true && exit 0

RUN apt-get update && apt-get install -y net-tools iptables
RUN mkdir -p /run/haproxy/
COPY ./haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY ./errors/400.http /etc/haproxy/errors/400.http
COPY ./errors/403.http /etc/haproxy/errors/403.http
COPY ./errors/408.http /etc/haproxy/errors/408.http
COPY ./errors/500.http /etc/haproxy/errors/500.http
COPY ./errors/502.http /etc/haproxy/errors/502.http
COPY ./errors/503.http /etc/haproxy/errors/503.http
COPY ./errors/504.http /etc/haproxy/errors/504.http

CMD ["haproxy", "-db", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]