FROM ubuntu:latest

EXPOSE 22

RUN apt update
RUN apt --assume-yes install ssh
RUN apt --assume-yes install rsyslog
RUN apt --assume-yes install netcat-traditional

RUN touch /etc/rsyslog.d/100-push.conf
RUN echo "*.* @connect:42514" >> /etc/rsyslog.d/100-push.conf

RUN adduser --gecos "" --disabled-password admin
RUN echo 'admin:admin' | chpasswd
RUN adduser --gecos "" --disabled-password test
RUN echo 'test:test' | chpasswd