FROM docker:19.03.12-dind-rootless@sha256:7606255ca83a7f516fae1b78299b79774f1f798ba9fc792a7231e7b0967ddb05
# Go into root
USER root
# Install your dependencies, this can be changed
RUN apk add git bash curl make vim
# Set the user back to the rootless user
USER rootless
# Setup docker
ENV DOCKER_HOST=unix:///var/run/user/1000/docker.sock