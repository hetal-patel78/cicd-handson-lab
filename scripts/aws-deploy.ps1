# AWS-Deploy.ps1
# Mirrors your company's AWS-Deploy.ps1 that runs inside Octopus.
# Creates or updates a CloudFormation stack that provisions ECS,
# ALB, Route53, auto-scaling, and EventBridge resources.
#
# In production, this script:
#   1. Assumes an AWS IAM role via STS for short-lived credentials
#   2. Reads configuration from SSM Parameter Store
#   3. Creates or updates the CloudFormation stack
#   4. Waits for the stack operation to complete
#
# In this lab, it targets LocalStack (local AWS mock).

param(
    [Parameter(Mandatory)]
    [string]$EnvironmentName,

    [Parameter(Mandatory)]
    [string]$ImageVersion,

    [string]$StackName = "MySubscriptionService-$EnvironmentName",
    [string]$TemplateFile = "$PSScriptRoot/../cloudformation/template.yml",
    [string]$Region = "us-east-1",
    [string]$AwsEndpointUrl = "http://localhost:4566",  # LocalStack endpoint

    # STS role assumption (simulated)
    [string]$RoleArn = "",
    [switch]$UseLocalStack = $true
)

Write-Host "🚀 Deploying stack: $StackName" -ForegroundColor Cyan
Write-Host "   Environment: $EnvironmentName" -ForegroundColor Cyan
Write-Host "   Image: $ImageVersion" -ForegroundColor Cyan

# ── Step 1: STS Role Assumption (simulated) ─────────────────
if ($RoleArn) {
    Write-Host "🔑 Assuming role: $RoleArn" -ForegroundColor Yellow
    # In production: Use-STSRole -RoleArn $RoleArn
    # In this lab: skipping, using local credentials
}

# ── Step 2: Read config from SSM Parameter Store (simulated) ─
Write-Host "📋 Reading configuration from SSM..." -ForegroundColor Yellow
$ssmParams = @{
    DesiredCount = if ($UseLocalStack) { 1 } else { 2 }
    MaximumCount = if ($UseLocalStack) { 2 } else { 8 }
    CpuTarget = 80
    MemoryTarget = 80
}
# In production: aws ssm get-parameter --name "/my-subscription/$EnvironmentName/config"

# ── Step 3: Build CloudFormation parameters ─────────────────
$cfParams = @(
    @{ ParameterKey = "EnvironmentName"; ParameterValue = $EnvironmentName },
    @{ ParameterKey = "ImageVersion"; ParameterValue = $ImageVersion },
    @{ ParameterKey = "DesiredCount"; ParameterValue = $ssmParams.DesiredCount.ToString() },
    @{ ParameterKey = "MaximumCount"; ParameterValue = $ssmParams.MaximumCount.ToString() },
    @{ ParameterKey = "CpuTargetValue"; ParameterValue = $ssmParams.CpuTarget.ToString() },
    @{ ParameterKey = "MemoryTargetValue"; ParameterValue = $ssmParams.MemoryTarget.ToString() }
)

# ── Step 4: Check if stack exists → Create or Update ───────
$awsArgs = @("cloudformation")
if ($UseLocalStack) {
    $awsArgs += "--endpoint-url=$AwsEndpointUrl"
}

try {
    $stackStatus = aws @awsArgs describe-stacks --stack-name $StackName --region $Region 2>$null | ConvertFrom-Json
    $stackExists = $true
    Write-Host "📦 Stack exists. Updating..." -ForegroundColor Yellow
} catch {
    $stackExists = $false
    Write-Host "📦 Stack does not exist. Creating..." -ForegroundColor Yellow
}

$operation = if ($stackExists) { "update-stack" } else { "create-stack" }

$paramsJson = $cfParams | ConvertTo-Json -Compress
$templateBody = Get-Content $TemplateFile -Raw

aws @awsArgs cloudformation $operation `
    --stack-name $StackName `
    --template-body file://$TemplateFile `
    --parameters $paramsJson `
    --capabilities CAPABILITY_NAMED_IAM `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Stack operation failed!" -ForegroundColor Red
    exit 1
}

# ── Step 5: Wait for completion ────────────────────────────
Write-Host "⏳ Waiting for stack operation to complete..." -ForegroundColor Yellow
if ($stackExists) {
    aws @awsArgs cloudformation wait stack-update-complete --stack-name $StackName --region $Region
} else {
    aws @awsArgs cloudformation wait stack-create-complete --stack-name $StackName --region $Region
}

Write-Host "✅ Stack $StackName deployed successfully!" -ForegroundColor Green

# ── Step 6: Output stack resources ─────────────────────────
Write-Host "`n📋 Stack Resources:" -ForegroundColor Cyan
aws @awsArgs cloudformation list-stack-resources --stack-name $StackName --region $Region | ConvertFrom-Json | `
    Select-Object -ExpandProperty StackResourceSummaries | `
    Format-Table LogicalResourceId, ResourceType, ResourceStatus -AutoSize
