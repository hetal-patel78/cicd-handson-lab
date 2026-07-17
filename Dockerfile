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

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 5210
ENV ASPNETCORE_URLS=http://+:5210
ENTRYPOINT ["dotnet", "MySubscriptionService.Api.dll"]