FROM centos:7

RUN yum -y update
RUN yum install -y bind
RUN /usr/sbin/rndc-confgen -a -b 512 -k rndc-key
RUN chmod 755 /etc/rndc.key

EXPOSE 53/UDP
EXPOSE 53/TCP

COPY named.conf /etc/bind/
COPY example.com /etc/bind/master/

CMD ["/usr/sbin/named", "-c", "/etc/bind/named.conf", "-g", "-u", "named"]