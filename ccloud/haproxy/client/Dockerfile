ARG TAG
FROM confluentinc/cp-kafkacat:${TAG}

USER root
RUN yum -y update && yum install -y iptables bind-utils net-tools
# How to install tcpdump on UBI8
RUN curl http://mirror.centos.org/centos/8/AppStream/x86_64/os/Packages/tcpdump-4.9.2-6.el8.x86_64.rpm -o tcpdump-4.9.2-6.el8.x86_64.rpm && rpm -Uvh tcpdump-4.9.2-6.el8.x86_64.rpm
CMD sleep infinity