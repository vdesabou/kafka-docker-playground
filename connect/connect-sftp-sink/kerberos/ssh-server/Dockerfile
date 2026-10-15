FROM --platform=linux/amd64 debian:bookworm

EXPOSE 22

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -qq update && \
    apt-get -qq install openssh-server krb5-user vim && \
    apt-get -qq clean && rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd

# configuration for the SSH server
COPY sshd_config /etc/ssh/sshd_config
# configuration for the SSH client
COPY ssh_config /etc/ssh/ssh_config
