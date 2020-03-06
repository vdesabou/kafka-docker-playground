FROM mcr.microsoft.com/dotnet/core/runtime:2.2-stretch-slim AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/core/sdk:2.2-stretch AS build
WORKDIR /src
COPY ["DotNet.csproj", "DotNet/"]
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