# Confluent C/C++ client: librdkafka from the Confluent clients apt repository
# (https://packages.confluent.io/clients/deb) for Debian 12 (bookworm), amd64 and arm64
# librdkafka version (packages librdkafka1 / librdkafka-dev <version>-1.cflt~deb12): DEFAULT_CLIENT_VERSION, or
# CLIENT_VERSION (optional, e.g. 2.3.0)
ARG DEFAULT_CLIENT_VERSION=2.16.0
ARG CLIENT_VERSION=""
FROM debian:bookworm-slim AS base
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && curl -fsSL https://packages.confluent.io/clients/deb/archive.key | gpg --dearmor -o /usr/share/keyrings/confluent-clients.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/confluent-clients.gpg] https://packages.confluent.io/clients/deb bookworm main" > /etc/apt/sources.list.d/confluent-clients.list \
    && apt-get update \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build
ARG DEFAULT_CLIENT_VERSION
ARG CLIENT_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev "librdkafka-dev=${CLIENT_VERSION:-$DEFAULT_CLIENT_VERSION}-*" "librdkafka++1=${CLIENT_VERSION:-$DEFAULT_CLIENT_VERSION}-*" "librdkafka1=${CLIENT_VERSION:-$DEFAULT_CLIENT_VERSION}-*" && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY client.c .
RUN gcc -std=c11 -Wall -Wextra -Werror -O2 -o client client.c -lrdkafka

FROM base
ARG DEFAULT_CLIENT_VERSION
ARG CLIENT_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends "librdkafka1=${CLIENT_VERSION:-$DEFAULT_CLIENT_VERSION}-*" && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/client /usr/local/bin/client
CMD ["sleep", "infinity"]
