FROM ubuntu:18.04
RUN apt-get update && \
    apt-get install -y openssh-server pwgen netcat net-tools curl wget && \
    apt-get clean all
# python and relevant tools
RUN apt-get update && apt-get install -y \
        build-essential software-properties-common \
 python \
 python-dev \
 libxml2-dev \
 libxslt-dev \
 libssl-dev \
 zlib1g-dev \
 libyaml-dev \
 libffi-dev \
 python-pip
# Latest versions of python tools via pip
RUN pip install --upgrade pip \
 virtualenv \
 requests
RUN ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
RUN mkdir /var/run/sshd
RUN sed -ri 's/^PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
# using https://github.com/gdraheim/docker-systemctl-replacement
RUN wget https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl.py -O /usr/bin/systemctl
RUN chmod u+rwx /usr/bin/systemctl
# using https://github.com/gdraheim/docker-systemctl-replacement
CMD ["/usr/bin/systemctl"]