# Confluent Go client (confluent-kafka-go v2, with a bundled static librdkafka: cgo, glibc) with the Avro serializer
# for Schema Registry
FROM golang:1.27-trixie AS build
WORKDIR /src
COPY go.mod go.sum ./
COPY main.go .
# CLIENT_VERSION (optional): another confluent-kafka-go v2 version than the one of go.mod, e.g. 2.12.0
ARG CLIENT_VERSION=""
RUN if [ -n "$CLIENT_VERSION" ]; then \
        go get "github.com/confluentinc/confluent-kafka-go/v2@v${CLIENT_VERSION#v}" && go mod tidy; \
    fi \
    && go mod download
RUN go vet ./... && CGO_ENABLED=1 go build -o /client .

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /client /usr/local/bin/client
CMD ["sleep", "infinity"]
