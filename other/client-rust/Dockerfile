# Confluent Rust client (crate confluent-kafka): a native Rust implementation
# of the Kafka protocol, no librdkafka. Needs Rust 1.95 or later.
FROM rust:1.95-slim-trixie AS build
# aws-lc-rs (TLS backend, default feature) builds C code with cmake
RUN apt-get update && apt-get install -y --no-install-recommends cmake && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Cargo.toml .
COPY src src
RUN cargo build --release --bins

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/producer /app/target/release/consumer /usr/local/bin/
CMD ["sleep", "infinity"]
