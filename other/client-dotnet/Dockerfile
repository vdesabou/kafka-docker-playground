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
COPY ["${CSPROJ_FILE}", "DotNet/DotNet.csproj"]
COPY ["Program.cs", "DotNet/"]
RUN dotnet restore "DotNet/DotNet.csproj"
COPY . .
WORKDIR "/src/DotNet"
RUN dotnet build "DotNet.csproj" -c Release -o /app

FROM build AS publish
RUN dotnet publish "DotNet.csproj" -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
CMD sleep infinity
# ENTRYPOINT ["dotnet", "DotNet.dll"]