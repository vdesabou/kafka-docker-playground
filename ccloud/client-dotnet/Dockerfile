FROM mcr.microsoft.com/dotnet/core/runtime:2.2-stretch-slim AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/core/sdk:2.2-stretch AS build
WORKDIR /src
COPY ["CCloud.csproj", "CCloud/"]
COPY ["Program.cs", "CCloud/"]
RUN dotnet restore "CCloud/CCloud.csproj"
COPY . .
WORKDIR "/src/CCloud"
RUN dotnet build "CCloud.csproj" -c Release -o /app

FROM build AS publish
RUN dotnet publish "CCloud.csproj" -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "CCloud.dll"]