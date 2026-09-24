FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["TrustApi.csproj", "TrustApi.csproj"]
RUN dotnet restore "TrustApi.csproj"
COPY . .
RUN dotnet publish "TrustApi.csproj" -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
# Render sets PORT (often 10000); bind to it when present so health checks reach the app.
ENTRYPOINT ["sh", "-c", "exec env ASPNETCORE_URLS=http://+:${PORT:-8080} dotnet TrustApi.dll"]
