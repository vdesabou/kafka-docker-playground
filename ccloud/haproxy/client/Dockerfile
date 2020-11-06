ARG TAG
FROM confluentinc/cp-kafkacat:${TAG}

USER root
RUN yum -y update && yum install -y iptables bind-utils net-tools
CMD sleep infinity