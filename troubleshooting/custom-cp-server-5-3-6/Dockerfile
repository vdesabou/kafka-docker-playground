# docker build -t vdesabou/cp-server:5.3.6 .
FROM confluentinc/cp-server:5.3.6
COPY run /etc/confluent/docker/run
RUN ["chmod", "+x", "/etc/confluent/docker/run"]