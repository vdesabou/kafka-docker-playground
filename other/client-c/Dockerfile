# Confluent C/C++ client: librdkafka from the Confluent clients apt repository
# (https://packages.confluent.io/clients/deb), latest 2.x release for Debian 12 (bookworm), amd64 and arm64
FROM debian:bookworm-slim AS base
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && curl -fsSL https://packages.confluent.io/clients/deb/archive.key | gpg --dearmor -o /usr/share/keyrings/confluent-clients.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/confluent-clients.gpg] https://packages.confluent.io/clients/deb bookworm main" > /etc/apt/sources.list.d/confluent-clients.list \
    && apt-get update \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev librdkafka-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY client.c .
RUN gcc -std=c11 -Wall -Wextra -Werror -O2 -o client client.c -lrdkafka

FROM base
RUN apt-get update && apt-get install -y --no-install-recommends librdkafka1 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/client /usr/local/bin/client
CMD ["sleep", "infinity"]
