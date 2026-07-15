# verify-deployment.ps1
# Validates that a CloudFormation deployment created all expected
# AWS resources. Run this AFTER aws-deploy.ps1 to confirm the
# pipeline's infrastructure provisioning worked correctly.
#
# This mirrors what you'd do in production: query AWS APIs to
# verify the stack is healthy and all resources exist.
#
# In an interview, you'd say:
# "We verify deployments by querying CloudFormation stack status,
# then checking each resource type (ECS task definitions, log
# groups, scaling policies) exist and have correct configuration."

param(
    [string]$StackName = "MySubscriptionService-test",
    [string]$Region = "us-east-1",
    [string]$AwsEndpointUrl = "http://localhost:4566"
)

$awsArgs = @("--endpoint-url=$AwsEndpointUrl")
$passed = 0
$failed = 0

function Test-Check {
    param($Name, $ScriptBlock)
    try {
        $result = & $ScriptBlock
        if ($result) {
            Write-Host "  ✅ $Name" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ❌ $Name" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  ❌ $Name - Error: $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "`n🔍 Verifying CloudFormation deployment: $StackName" -ForegroundColor Cyan
Write-Host "===========================================`n" -ForegroundColor Cyan

# ── 1. Stack exists and is in a good state ─────────────────
Write-Host "1. Stack Status" -ForegroundColor Yellow
$stackOk = Test-Check "Stack exists and is in CREATE_COMPLETE or UPDATE_COMPLETE state" {
    $stack = aws @awsArgs cloudformation describe-stacks --stack-name $StackName --region $Region 2>$null | ConvertFrom-Json
    $status = $stack.Stacks[0].StackStatus
    $status -match "CREATE_COMPLETE|UPDATE_COMPLETE"
}

if ($stackOk) { $passed++ } else { $failed++ }

# ── 2. List all resources in the stack ─────────────────────
Write-Host "`n2. Resources Created" -ForegroundColor Yellow
$resources = aws @awsArgs cloudformation list-stack-resources --stack-name $StackName --region $Region 2>$null | ConvertFrom-Json
$resourceSummaries = $resources.StackResourceSummaries

$expectedResources = @(
    @{ LogicalId = "ECSCluster"; Type = "AWS::ECS::Cluster" },
    @{ LogicalId = "ServiceLogGroup"; Type = "AWS::Logs::LogGroup" },
    @{ LogicalId = "JobLogGroup"; Type = "AWS::Logs::LogGroup" },
    @{ LogicalId = "ServiceTaskRole"; Type = "AWS::IAM::Role" },
    @{ LogicalId = "ServiceTaskDefinition"; Type = "AWS::ECS::TaskDefinition" },
    @{ LogicalId = "ServiceTargetGroup"; Type = "AWS::ElasticLoadBalancingV2::TargetGroup" },
    @{ LogicalId = "ServiceSecurityGroup"; Type = "AWS::EC2::SecurityGroup" },
    @{ LogicalId = "ECSService"; Type = "AWS::ECS::Service" },
    @{ LogicalId = "ServiceAutoScalingTarget"; Type = "AWS::ApplicationAutoScaling::ScalableTarget" },
    @{ LogicalId = "ServiceCpuScalingPolicy"; Type = "AWS::ApplicationAutoScaling::ScalingPolicy" },
    @{ LogicalId = "ServiceMemoryScalingPolicy"; Type = "AWS::ApplicationAutoScaling::ScalingPolicy" },
    @{ LogicalId = "ScheduledJobTaskDefinition"; Type = "AWS::ECS::TaskDefinition" },
    @{ LogicalId = "ScheduledJobEventBridgeRule"; Type = "AWS::Events::Rule" },
    @{ LogicalId = "ServiceDnsRecord"; Type = "AWS::Route53::RecordSet" }
)

foreach ($expected in $expectedResources) {
    $found = $resourceSummaries | Where-Object {
        $_.LogicalResourceId -eq $expected.LogicalId -and $_.ResourceType -eq $expected.Type -and
        $_.ResourceStatus -eq "CREATE_COMPLETE"
    }
    if ($found) {
        Write-Host "  ✅ $($expected.LogicalId) ($($expected.Type))" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ❌ $($expected.LogicalId) ($($expected.Type)) - not found or not CREATE_COMPLETE" -ForegroundColor Red
        $failed++
    }
}

# ── 3. Verify specific resource properties ─────────────────
Write-Host "`n3. Resource Configuration Checks" -ForegroundColor Yellow

Test-Check "ECS Cluster exists" {
    $clusters = aws @awsArgs ecs describe-clusters --clusters "my-subscription-test" --region $Region 2>$null | ConvertFrom-Json
    $clusters.clusters[0].clusterName -eq "my-subscription-test"
}

Test-Check "Service Task Definition exists with FARGATE" {
    $td = aws @awsArgs ecs describe-task-definition --task-definition "my-subscription-service-test" --region $Region 2>$null | ConvertFrom-Json
    $td.taskDefinition.requiresCompatibilities -contains "FARGATE"
}

Test-Check "Log Group exists" {
    $logs = aws @awsArgs logs describe-log-groups --log-group-name-prefix "/ecs/my-subscription-service" --region $Region 2>$null | ConvertFrom-Json
    $logs.logGroups.Count -gt 0
}

Test-Check "Auto Scaling target exists" {
    $scaling = aws @awsArgs application-autoscaling describe-scalable-targets --service-namespace ecs --resource-ids "service/my-subscription-test/my-subscription-service-test" --region $Region 2>$null | ConvertFrom-Json
    $scaling.scalableTargets.Count -gt 0
}

Test-Check "EventBridge rule exists with schedule" {
    $rules = aws @awsArgs events list-rules --name-prefix "clear-subscription-data-test" --region $Region 2>$null | ConvertFrom-Json
    $rules.Rules[0].ScheduleExpression -match "cron"
}

# ── 4. Stack outputs ───────────────────────────────────────
Write-Host "`n4. Stack Outputs" -ForegroundColor Yellow
$outputs = aws @awsArgs cloudformation describe-stacks --stack-name $StackName --region $Region 2>$null | ConvertFrom-Json
foreach ($output in $outputs.Stacks[0].Outputs) {
    Write-Host "   $($output.OutputKey) = $($output.OutputValue)" -ForegroundColor Gray
}

# ── Summary ─────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "📊 Verification Results:" -ForegroundColor Cyan
Write-Host "   Passed: $passed" -ForegroundColor Green
Write-Host "   Failed: $failed" -ForegroundColor Red
Write-Host "   Total:  $($passed + $failed)" -ForegroundColor Cyan

if ($failed -eq 0) {
    Write-Host "`n✅ ALL CHECKS PASSED - Infrastructure provisioned correctly!" -ForegroundColor Green
} else {
    Write-Host "`n❌ $failed check(s) failed - Review errors above." -ForegroundColor Red
}
