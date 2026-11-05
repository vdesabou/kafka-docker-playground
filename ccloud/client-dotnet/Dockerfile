# Confluent .NET client (Confluent.Kafka, on librdkafka) with the Avro serializer for Schema Registry, on .NET 10 (LTS)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ClientDotnet.csproj .
# CLIENT_VERSION (optional): another Confluent.Kafka (and Confluent.SchemaRegistry.Serdes.Avro) version than the one of
# ClientDotnet.csproj, e.g. 2.3.0
ARG CLIENT_VERSION=""
RUN if [ -n "$CLIENT_VERSION" ]; then \
        dotnet add package Confluent.Kafka --version "$CLIENT_VERSION" --no-restore \
        && dotnet add package Confluent.SchemaRegistry.Serdes.Avro --version "$CLIENT_VERSION" --no-restore; \
    fi \
    && dotnet restore
COPY Program.cs .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/runtime:10.0
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "ClientDotnet.dll"]
