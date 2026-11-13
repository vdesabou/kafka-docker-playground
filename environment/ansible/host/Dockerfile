# A cp-ansible target host: Ubuntu 24.04 with systemd as PID 1, the image cp-ansible's own molecule tests use
# (molecule/Dockerfile-ubuntu-archive.j2), plus a JDK so that the playbook does not install one on every run (a JDK, not
# a JRE: playground debug heap-dump / thread-dump need jmap and jcmd)
FROM geerlingguy/docker-ubuntu2404-ansible
# /usr/share/man/man1 is missing in the image: without it the java packages fail (update-alternatives on java.1.gz)
RUN mkdir -p /usr/share/man/man1 \
 && apt-get update -y \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends default-jdk-headless ca-certificates curl jq \
 && rm -rf /var/lib/apt/lists/*
