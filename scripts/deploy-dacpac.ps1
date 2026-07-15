# Deploy-Dacpac.ps1
# Mirrors your company's Deploy-Dacpac-Local.ps1.
# Deploys the database schema (DACPAC) to SQL Server.
# In production, this runs as a separate Octopus project.
# In this lab, it creates a local SQL Server container.

param(
    [string]$SqlServer = "localhost,1433",
    [string]$Database = "MySubscriptionService",
    [string]$SaPassword = "LocalStack!123",
    [string]$DacpacPath = "$PSScriptRoot/../database/MySubscriptionService.dacpac"
)

Write-Host "🗄️  Deploying database: $Database" -ForegroundColor Cyan

# ── Start SQL Server in Docker ─────────────────────────────
Write-Host "   Starting SQL Server container..." -ForegroundColor Yellow
docker rm -f mssql-subscription 2>$null
docker run -d --name mssql-subscription `
    -e "ACCEPT_EULA=Y" `
    -e "MSSQL_SA_PASSWORD=$SaPassword" `
    -p 1433:1433 `
    mcr.microsoft.com/mssql/server:2022-latest

Write-Host "⏳ Waiting for SQL Server to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# ── Deploy DACPAC (simulated - creates database) ──────────
Write-Host "   Creating database..." -ForegroundColor Yellow
$sqlCmd = @"
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '$Database')
BEGIN
    CREATE DATABASE [$Database];
    PRINT 'Database created';
END
ELSE
    PRINT 'Database already exists';
"@

docker exec mssql-subscription /opt/mssql-tools/bin/sqlcmd `
    -S localhost -U sa -P "$SaPassword" `
    -Q $sqlCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Database '$Database' deployed successfully!" -ForegroundColor Green
    Write-Host "   Connection: Server=$SqlServer;Database=$Database;User=sa;Password=$SaPassword;TrustServerCertificate=true"
} else {
    Write-Host "❌ Database deployment failed!" -ForegroundColor Red
}
