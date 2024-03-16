# There may be a newer version
FROM docker:19.03.12-dind-rootless
# Go into root
USER root
# Install your dependencies, this can be changed
RUN apk add git bash curl make vim go
# Set the user back to the rootless user
USER rootless
# Setup docker
ENV DOCKER_HOST=unix:///var/run/user/1000/docker.sock