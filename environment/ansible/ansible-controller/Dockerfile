# The Ansible controller: ansible-core and the confluent.platform collection (cp-ansible) at the versions of the case.
# Ansible reaches the hosts with the community.docker.docker connection (docker exec), not SSH, as cp-ansible's molecule tests do
FROM python:3.12-slim
ARG ANSIBLE_CORE_VERSION=2.17.*
# a version or a range: ">=8.4.0,<8.5.0" picks the latest 8.4.x on Ansible Galaxy
ARG CP_ANSIBLE_VERSION=">=8.4.0,<8.5.0"
COPY --from=docker:cli /usr/local/bin/docker /usr/local/bin/docker
# bcrypt: the only python module the plugins of cp-ansible need on the controller (Control Center passwords)
RUN pip install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSION}" docker bcrypt \
 && ansible-galaxy collection install "confluent.platform:${CP_ANSIBLE_VERSION}" community.docker ansible.posix community.general
COPY ansible.cfg /etc/ansible/ansible.cfg
ENV ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_FORCE_COLOR=1
CMD ["sleep", "infinity"]
