# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ClaimStatusApi.sln ./
COPY src/ClaimStatusApi/ClaimStatusApi.csproj src/ClaimStatusApi/
RUN dotnet restore
COPY . .
RUN dotnet publish src/ClaimStatusApi/ClaimStatusApi.csproj -c Release -o /app/publish /p:UseAppHost=false

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
# Expose port (ACA/APIM will map)
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "ClaimStatusApi.dll"]
