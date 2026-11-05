# Confluent Go client (confluent-kafka-go v2, with a bundled static librdkafka: cgo, glibc) with the Avro serializer
# for Schema Registry
FROM golang:1.27-trixie AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go .
RUN go vet ./... && CGO_ENABLED=1 go build -o /client .

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /client /usr/local/bin/client
CMD ["sleep", "infinity"]
