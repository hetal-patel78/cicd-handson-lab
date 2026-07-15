# Multi-stage Docker build
# Stage 1: Build the application
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/MySubscriptionService.sln .
COPY src/MySubscriptionService.Core/*.csproj MySubscriptionService.Core/
COPY src/MySubscriptionService.Api/*.csproj MySubscriptionService.Api/
RUN dotnet restore
COPY src/ .
RUN dotnet publish MySubscriptionService.Api/MySubscriptionService.Api.csproj \
    --configuration Release \
    --output /app/publish

# Stage 2: Create the runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 80
ENV ASPNETCORE_URLS=http://+:80
ENTRYPOINT ["dotnet", "MySubscriptionService.Api.dll"]
