# setup-localstack.ps1
# Starts LocalStack in Docker and pre-configures it for testing.
# LocalStack simulates AWS services locally (CloudFormation, ECS,
# IAM, CloudWatch, etc.) so you can test deployments without
# touching real AWS.

param(
    [string]$LocalStackImage = "localstack/localstack:3.0",
    [int]$Port = 4566
)

Write-Host "🔧 Starting LocalStack..." -ForegroundColor Cyan

# ── Check if Docker is running ─────────────────────────────
try {
    docker info 2>$null | Out-Null
} catch {
    Write-Host "❌ Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

# ── Start LocalStack container ─────────────────────────────
Write-Host "   Image: $LocalStackImage" -ForegroundColor Gray
Write-Host "   Port: $Port" -ForegroundColor Gray

docker run -d `
    --name localstack `
    -p $Port`:4566 `
    -e SERVICES="cloudformation,ecs,iam,logs,ssm,sts,elasticloadbalancing,route53,application-autoscaling,events" `
    -e AWS_DEFAULT_REGION=us-east-1 `
    -e AWS_ACCESS_KEY_ID=test `
    -e AWS_SECRET_ACCESS_KEY=test `
    $LocalStackImage

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to start LocalStack. Retrying without --rm..." -ForegroundColor Red
    docker rm localstack 2>$null
    docker run -d --name localstack -p $Port`:4566 $LocalStackImage
}

Write-Host "⏳ Waiting for LocalStack to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# ── Verify LocalStack is running ───────────────────────────
try {
    $health = Invoke-RestMethod -Uri "http://localhost:$Port/_localstack/health" -ErrorAction Stop
    $available = ($health.services | Get-Member -MemberType NoteProperty).Name | Where-Object {
        $health.services.$_ -eq "available"
    }
    Write-Host "✅ LocalStack running! Available services: $($available -join ', ')" -ForegroundColor Green
} catch {
    Write-Host "❌ LocalStack not responding. Check docker logs: docker logs localstack" -ForegroundColor Red
    exit 1
}

# ── Pre-create VPC/Subnet for CloudFormation ───────────────
Write-Host "🔧 Pre-creating VPC and subnets..." -ForegroundColor Yellow
aws --endpoint-url=http://localhost:$Port ec2 create-vpc --cidr-block 10.0.0.0/16 --region us-east-1 | Out-Null
aws --endpoint-url=http://localhost:$Port ec2 create-subnet --cidr-block 10.0.1.0/24 --vpc-id vpc-00000000 --region us-east-1 | Out-Null

Write-Host "✅ LocalStack ready at http://localhost:$Port" -ForegroundColor Green
