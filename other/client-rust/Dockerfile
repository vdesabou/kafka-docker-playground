# Confluent Rust client (crate confluent-kafka): a native Rust implementation
# of the Kafka protocol, no librdkafka. Needs Rust 1.95 or later.
FROM rust:1.95-slim-trixie AS build
# aws-lc-rs (TLS backend, default feature) builds C code with cmake
RUN apt-get update && apt-get install -y --no-install-recommends cmake && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Cargo.toml .
COPY src src
# CLIENT_VERSION (optional): another confluent-kafka crate version than the one of Cargo.toml, e.g. 1.0.0-rc.2
ARG CLIENT_VERSION=""
RUN if [ -n "$CLIENT_VERSION" ]; then \
        sed -i "s/^confluent-kafka = .*/confluent-kafka = \"=$CLIENT_VERSION\"/" Cargo.toml; \
    fi \
    && cargo build --release --bins \
    && cargo tree --depth 1 --prefix none | grep '^confluent-kafka ' > /app/client-version.txt

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/producer /app/target/release/consumer /usr/local/bin/
COPY --from=build /app/client-version.txt /usr/local/share/client-version.txt
CMD ["sleep", "infinity"]
