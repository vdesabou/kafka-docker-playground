# Confluent .NET client (Confluent.Kafka, on librdkafka) with the Avro serializer for Schema Registry, on .NET 10 (LTS)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ClientDotnet.csproj .
RUN dotnet restore
COPY Program.cs .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/runtime:10.0
WORKDIR /app
COPY --from=build /app .
CMD ["sleep", "infinity"]
