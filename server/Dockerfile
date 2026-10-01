# syntax=docker/dockerfile:1
# Build context is the repo root (the image needs /contracts and /data), see docker-compose.yml.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY server/global.json server/Directory.Build.props server/
COPY server/src/DoZore.Api/DoZore.Api.csproj server/src/DoZore.Api/
RUN dotnet restore server/src/DoZore.Api/DoZore.Api.csproj
COPY server/src/ server/src/
RUN dotnet publish server/src/DoZore.Api/DoZore.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
COPY contracts/ contracts/
COPY data/ data/
COPY server/seed/ seed/
ENV PORT=8080 \
    ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "DoZore.Api.dll"]
