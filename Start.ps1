# Start.ps1
# Local analogue of the CI "deploy" step.
# Builds and runs the service locally via Docker.
# In your company, this mirrors Start.ps1 at the repo root.

Write-Host "🚀 Building Docker image..." -ForegroundColor Cyan
docker build -t my-subscription-service:local .

Write-Host "🚀 Starting container..." -ForegroundColor Cyan
docker run -d --name my-subscription-service -p 8080:80 my-subscription-service:local

Write-Host "✅ Service running at http://localhost:8080" -ForegroundColor Green
Write-Host "   Try: curl http://localhost:8080/api/subscriptions" -ForegroundColor Yellow
