# Test.ps1
# Local analogue of the CI unit-tests + integration-tests jobs.
# Runs all test projects with coverage collection.
# In your company, this mirrors Test.ps1 at the repo root.

$Configuration = "Release"
$SolutionPath = "src\MySubscriptionService.sln"

Write-Host "🧪 Restoring..." -ForegroundColor Cyan
dotnet restore $SolutionPath

Write-Host "🧪 Running unit tests..." -ForegroundColor Cyan
dotnet test tests\MySubscriptionService.UnitTests\MySubscriptionService.UnitTests.csproj `
    --configuration $Configuration `
    --no-restore `
    --collect:"XPlat Code Coverage" `
    --results-directory "$PSScriptRoot\coverage\unit"

Write-Host "🧪 Running integration tests..." -ForegroundColor Cyan
dotnet test tests\MySubscriptionService.IntegrationTests\MySubscriptionService.IntegrationTests.csproj `
    --configuration $Configuration `
    --no-restore `
    --collect:"XPlat Code Coverage" `
    --results-directory "$PSScriptRoot\coverage\integration"

Write-Host "🧪 Generating merged coverage report..." -ForegroundColor Cyan
dotnet tool install -g dotnet-reportgenerator-globaltool --quiet 2>$null
reportgenerator `
    -reports:"$PSScriptRoot\coverage\**\coverage.cobertura.xml" `
    -targetdir:"$PSScriptRoot\coverage-report" `
    -reporttypes:"Html"

Write-Host "✅ Tests complete! Open coverage-report\index.html to view." -ForegroundColor Green
