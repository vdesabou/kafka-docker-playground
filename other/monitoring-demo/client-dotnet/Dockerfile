ARG CORE_RUNTIME_TAG
ARG CORE_SDK_TAG
ARG CSPROJ_FILE
FROM mcr.microsoft.com/dotnet/core/runtime:${CORE_RUNTIME_TAG} AS base
WORKDIR /app

ARG CORE_SDK_TAG
ARG CSPROJ_FILE
FROM mcr.microsoft.com/dotnet/core/sdk:${CORE_SDK_TAG} AS build
WORKDIR /src
ARG CSPROJ_FILE
COPY [ "${CSPROJ_FILE}", "Monitoring/Monitoring.csproj"]
COPY ["Program.cs", "Monitoring/"]
COPY ["Statistics.cs", "Monitoring/"]
RUN dotnet restore "Monitoring/Monitoring.csproj"
COPY . .
WORKDIR "/src/Monitoring"
RUN dotnet build "Monitoring.csproj" -c Release -o /app

FROM build AS publish
RUN dotnet publish "Monitoring.csproj" -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
CMD sleep infinity