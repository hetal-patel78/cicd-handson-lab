# Stop.ps1
# Stops and removes the local container.
# In your company, this mirrors Stop.ps1 at the repo root.

Write-Host "🛑 Stopping container..." -ForegroundColor Cyan
docker stop my-subscription-service 2>$null
docker rm my-subscription-service 2>$null

Write-Host "✅ Container stopped and removed." -ForegroundColor Green
