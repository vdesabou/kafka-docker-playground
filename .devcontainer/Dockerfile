FROM docker:24.0.9-dind-rootless
# Go into root
USER root
# Install your dependencies, this can be changed
RUN apk add git bash curl make vim
# Set the user back to the rootless user
USER rootless
# Setup docker
ENV DOCKER_HOST=unix:///var/run/user/1000/docker.sock