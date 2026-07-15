# MySubscriptionService — CI/CD Hands-On Lab

This lab mirrors the architecture of a **real-world enterprise CI/CD pipeline** (inspired by Xero's Billing Subscription Service). Every file and config here has a counterpart in a production system. Use this to understand the _why_ behind each piece, not just the _what_.

---

## 1. The Big Picture

```
Developer pushes code / opens PR
        │
        ▼
┌─────────────────────────────────────────────────────┐
│                 GitHub Actions                       │
│  ┌────────┐  ┌──────────┐  ┌─────────┐  ┌────────┐ │
│  │Version │  │  Build   │  │  Test   │  │Quality │ │
│  │GitVer. │──│  .NET    │──│ Unit+Int│──│Sonar+  │ │
│  └────────┘  └──────────┘  └─────────┘  │Coverage│ │
│                                          └────────┘ │
│  ┌────────┐  ┌──────────────┐                        │
│  │Publish │  │Octopus       │                        │
│  │Docker+ │──│Release Create│                        │
│  │NuGet   │  └──────────────┘                        │
│  └────────┘                                          │
└─────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────┐
│              Octopus Deploy → AWS                    │
│  CloudFormation → ECS + ALB + R53 + AutoScaling     │
│  DACPAC → SQL Server                                 │
└─────────────────────────────────────────────────────┘
```

**Three pipeline paths** (same workflow, different jobs run):
| Trigger | What runs | Purpose |
|---------|-----------|---------|
| **PR** to main/feature | Build + Test + Coverage + Sonar + Auto-Approve | Validate code before merge |
| **Push** to feature/* | Above + Publish + Octopus Release (Test/UAT) | Deploy to lower environments |
| **Push** to main | Above + Octopus Release (Test/UAT/Prod) | Full path to production |

> **Interview Tip**: "Our pipeline uses **conditional job execution** — the same workflow YAML behaves differently based on `github.event_name` and branch. PRs only validate; pushes publish and release. This avoids duplicating workflow files."

---

---

### 1.1 End-to-End: What the Full Pipeline Does

```
Developer commits code
        │
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                    GITHUB ACTIONS (CI)                           │
│                                                                  │
│  version ──► application-build ──► docker-nuget-publish         │
│  version ──► unit-tests ──► project-coverage ──► sonar-analysis │
│  version ──► integration-tests ──► project-coverage              │
│                                                                  │
│  docker-nuget-publish ──► create-octopus-release                 │
└──────────────────────────────────────────────────────────────────┘
        │ Octopus release created
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                    OCTOPUS DEPLOY (CD)                           │
│                                                                  │
│  1. Assume AWS IAM role via STS  (short-lived credentials)      │
│  2. Read config from AWS SSM Parameter Store                    │
│  3. Deploy Deploy Script NuGet package                          │
│                                                                  │
│  ┌─────────────────────┐    ┌────────────────────┐               │
│  │  App Deployment     │    │  DB Deployment     │               │
│  │  AWS-Deploy.ps1     │    │  Deploy-Dacpac.ps1 │               │
│  └─────────┬───────────┘    └─────────┬──────────┘               │
│            ▼                          ▼                          │
│  CloudFormation stack           SqlPackage publishes            │
│  (create/update)                DACPAC to SQL Server            │
└──────────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────────┐
│            AWS RESOURCES PROVISIONED                             │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  ECS Task Definition (Fargate)                           │   │
│  │  ALB Target Group + Listener Rule                        │   │
│  │  Route53 CNAME Record                                   │   │
│  │  Auto Scaling (CPU + Memory)                            │   │
│  │  CloudWatch Log Groups                                  │   │
│  │  Security Group                                         │   │
│  │  EventBridge Rule → ECS RunTask (scheduled job)         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  DeployTrack records New Relic marker + posts to Slack          │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Directory Layout

```
cicd-handson-lab/
├── .github/
│   ├── workflows/
│   │   └── ci-cd-pipeline.yml      # THE pipeline (study this most)
│   ├── scripts/
│   │   ├── version.sh              # GitVersion → version strings
│   │   └── auto-approve-pr.sh      # Auto-approve trusted PRs
│   └── tvm/
│       └── policy.yaml             # Token Vending Machine policy
├── .batect/
│   └── development.yml             # Containerised dev/test env
├── cloudformation/
│   └── template.yml                # AWS CloudFormation template
├── scripts/
│   ├── aws-deploy.ps1              # STS assume → SSM → CF create/update
│   ├── deploy-dacpac.ps1           # SQL Server DACPAC deployment
│   ├── setup-localstack.ps1        # LocalStack AWS mock bootstrap
│   └── verify-deployment.ps1       # Post-deployment resource validation
├── src/
│   ├── MySubscriptionService.sln
│   ├── MySubscriptionService.Api/  # ASP.NET Web API
│   └── MySubscriptionService.Core/ # Domain logic
├── tests/
│   ├── MySubscriptionService.UnitTests/
│   └── MySubscriptionService.IntegrationTests/
├── Dockerfile                       # Multi-stage Docker build
├── GitVersion.yml                   # Semantic versioning rules
├── batect.yml                       # Containerised task runner
├── deploytrack.yaml                 # Release governance config
├── Build.ps1                        # Local build
├── Test.ps1                         # Local test + coverage
├── Start.ps1                        # Local Docker run
└── Stop.ps1                         # Local Docker stop
```

---

## 3. Deep Dive: Every Component Explained

### 3.1 GitHub Actions (`ci-cd-pipeline.yml`)

**What it is**: The orchestration layer. It defines WHEN things run (triggers), WHAT runs (jobs), and IN WHAT ORDER (needs/dependencies).

**Key concepts to understand for interviews**:

| Concept | How it's used here | Why it matters |
|---------|-------------------|----------------|
| **Events** | `push`, `pull_request`, `workflow_dispatch` | The pipeline reacts differently to each |
| **Concurrency** | One run per branch; PRs cancel-in-progress | Prevents wasted builds on stale code |
| **Jobs** | `version`, `application-build`, `unit-tests`, etc. | Each is a unit of work with its own runner |
| **`needs:`** | `application-build needs: [version]` | Creates the execution DAG |
| **`if:` conditions** | `if: github.event_name == 'push'` | Same YAML → different behavior per trigger |
| **Artifacts** | Upload/download between jobs | Passes build output without rebuilding |
| **Secrets** | `${{ secrets.SONAR_TOKEN }}` | Sensitive values never in code |
| **Matrix builds** | (Not shown, but common) | Test across multiple OS/versions |

> **Interview Tip**: "Our pipeline uses a DAG-based approach with `needs:`. Tests and build run in parallel after versioning, then converge at publish. This minimizes total wall-clock time."

### 3.2 GitVersion (`GitVersion.yml`)

**What it does**: Derives a semantic version (e.g., `1.2.3-feature.1+0`) from git history. Every commit gets a unique, deterministic version.

**Why it exists**: Without it, teams manually bump version numbers, which is error-prone and causes conflicts. GitVersion uses branch names and commit history to automate this.

**Key concepts**:
- **ContinuousDeployment mode**: Every commit gets a unique pre-release tag
- **Branch rules**: `main` → patch bump, `feature/*` → minor bump + `-feature` tag
- **Source of truth**: The same version flows into the assembly, Docker tag, NuGet package, and Octopus release

> **Interview Tip**: "GitVersion gives us a **single source of truth for versioning**. The `version` job outputs `semVer` and `imageTag`, which every downstream job consumes via `needs.version.outputs.*`. This guarantees a build, its Docker image, and its Octopus release all carry the same identifier."

### 3.3 Build (`application-build` job + `Build.ps1`)

**What happens**:
1. Checkout code (including submodules like a shared library)
2. Restore NuGet dependencies
3. Compile the .NET solution
4. Publish to a staging folder
5. Upload artifacts for downstream jobs

**Why separate build and test?** So publish/test can run in parallel. The build job produces artifacts once; test jobs consume them.

> **Interview Tip**: "We use **immutable build artifacts**. The build job compiles once and uploads the output. Later jobs download rather than rebuild. This guarantees that what was tested is exactly what gets deployed — no recompilation drift."

### 3.4 Testing (unit + integration + coverage)

| Test type | What it validates | Tooling |
|-----------|------------------|---------|
| **Unit** | Individual classes/methods in isolation | xUnit + FluentAssertions |
| **Integration** | API endpoints against a real server | `WebApplicationFactory` + HttpClient |
| **Coverage** | What percentage of code is tested | Coverlet + ReportGenerator |

**Key concept — batect**: In your company, tests run inside **batect** containers. This ensures CI and local dev use the identical toolchain. The `development.yml` defines the same tasks that both CI and `./batect unit-test` use locally.

> **Interview Tip**: "**batect** eliminates environment inconsistency. The same YAML config defines test containers locally and in CI. If a test passes on a developer's machine, it _will_ pass in CI — because it's literally the same container image and commands."

### 3.5 SonarCloud (`sonar-analysis` job)

**What it does**: Static code analysis — detects bugs, code smells, security vulnerabilities, and duplicate code. It enforces a **quality gate** that can block the pipeline.

The key parameter:
```yaml
/d:sonar.qualitygate.wait=true
```

This tells SonarCloud: "Don't let the pipeline continue until the quality gate passes or fails."

> **Interview Tip**: "SonarCloud with `qualitygate.wait=true` is our **non-negotiable quality barrier**. If the code introduces a critical vulnerability or drops below coverage thresholds, the pipeline fails before the code can merge. This prevents technical debt from accumulating."

### 3.6 Docker + Artifactory (`docker-nuget-publish` job)

After validation passes (on pushes only), the pipeline:
1. Builds a Docker image using the multi-stage `Dockerfile`
2. Tags it with the version (e.g., `1.2.3-feature.1+0`)
3. Pushes to Artifactory (the company's private registry)

**Multi-stage Dockerfile** (why it matters):
- **Stage 1 (build)**: Full SDK — compiles the code
- **Stage 2 (runtime)**: Minimal ASP.NET runtime — only what's needed to run

This keeps the production image small (~200MB vs 1.8GB) and reduces the attack surface.

> **Interview Tip**: "We use **multi-stage Docker builds** to separate the build environment from the runtime. The final image contains only the compiled binaries and the ASP.NET runtime — no SDK, no build tools. This is both a security and a performance best practice."

### 3.7 Octopus Deploy (`create-octopus-release` job)

**What it does**: Creates a "release" object in Octopus Deploy. Octopus then handles the actual deployment (promoting through Test → UAT → Prod).

**Why two release jobs?** In your company, the app and the database are separate Octopus projects:
- **App release**: Deploys Docker images to ECS
- **DB release**: Deploys DACPAC to SQL Server

This separation lets each follow its own deployment cadence.

> **Interview Tip**: "Octopus is our **release management layer**. GitHub Actions stops at 'create a release in Octopus.' Octopus then handles environment promotion, approval gates, and rollbacks. This separation of concerns means CI doesn't need production credentials — only Octopus does."

### 3.8 DeployTrack / CAB (`deploytrack.yaml`)

**What it does**: Release governance — coordinates approvals, notifications, and observability markers.

Key capabilities:
- **CAB check**: Does this PR need Change Advisory Board approval? (Skipped if labelled `no cab required`)
- **New Relic markers**: Records every deployment so you can correlate code changes with performance
- **Slack notifications**: Different channels for lower environments vs. production

> **Interview Tip**: "DeployTrack enforces **release governance**. Changes to production require CAB approval unless explicitly labelled. This satisfies compliance/audit requirements. Every deployment also records a New Relic marker, so we can pinpoint which deployment caused a performance regression."

### 3.9 Infrastructure Provisioning (CloudFormation)

While not in this lab's code, your company's AWS infrastructure is provisioned by **CloudFormation** (invoked by Octopus, not Terraform). Key resources created:

| Resource | Purpose |
|----------|---------|
| ECS Task Definition | Defines the container (CPU, memory, image) |
| ALB Target Group + Listener Rule | Routes traffic to the service |
| Security Group | Network access controls |
| Route53 Record | DNS name for the service |
| Auto Scaling | CPU/memory-based scaling |
| CloudWatch Log Group | Centralized logging |
| EventBridge Rule | Triggers scheduled jobs |

> **Interview Tip**: "Infrastructure is provisioned **declaratively via CloudFormation** during Octopus deployment. The pipeline packages a deploy script that assumes an AWS IAM role (via STS), reads parameters from SSM Parameter Store, and runs `CreateStack` or `UpdateStack`. This means infrastructure changes go through the same deployment process as application changes."

---

## 4. Interview Questions You Can Now Answer

### Q: "How does your CI/CD pipeline work end-to-end?"

**Answer**: "Our pipeline is defined in a single GitHub Actions workflow with conditional job execution. When a developer pushes code or opens a PR:
1. **Version** — GitVersion derives a semantic version from git history
2. **Build + Test in parallel** — The application compiles while unit and integration tests run in containers via batect
3. **Quality** — Coverage reports merge, and SonarCloud enforces a quality gate
4. **Publish** — On pushes (not PRs), Docker images and NuGet packages are pushed to Artifactory
5. **Release** — Octopus releases are created for the appropriate channel (Test/UAT for feature branches, all the way to Prod for main)

GitHub Actions handles CI; Octopus handles CD and environment promotions. Infrastructure is provisioned via CloudFormation during Octopus deployment."

### Q: "How do you ensure code quality doesn't slip?"

**Answer**: "We have a multi-layered quality strategy:
1. **Unit tests** catch logic errors early
2. **Integration tests** validate API contracts end-to-end
3. **Coverage merging** gives us a single, accurate picture of what's tested
4. **SonarCloud quality gate** blocks any change that introduces bugs, vulnerabilities, or drops below coverage thresholds
5. **CAB approval** is required for production deployments unless explicitly waived"

### Q: "How do you handle versioning?"

**Answer**: "We use **GitVersion in ContinuousDeployment mode**. It derives the version automatically from git history — no manual version bumps. The version job outputs a `semVer` string that flows into:
- The .NET assembly version
- The Docker image tag
- The NuGet package version  
- The Octopus release version

This guarantees traceability: given any deployed image, you can trace it back to the exact commit and build."

### Q: "How do you prevent 'works on my machine' issues?"

**Answer**: "We use **batect**, a containerised task runner. The same `development.yml` file defines test environments for both CI and local development. When a developer runs `./batect unit-test` locally and when CI runs it, they execute the exact same commands in the exact same container. If it passes locally, it passes in CI."

### Q: "What happens after the pipeline creates a release?"

**Answer**: "GitHub Actions hands off to **Octopus Deploy**. Octopus promotes the release through environments (Test → UAT → Production). During deployment, Octopus runs a PowerShell script that:
1. Assumes an AWS IAM role via STS for short-lived credentials
2. Reads configuration from SSM Parameter Store
3. Creates or updates a CloudFormation stack that provisions ECS services, ALB routing, DNS, auto-scaling, and logging

The database is deployed separately via SqlPackage and a DACPAC. All of this is tracked by **DeployTrack**, which posts to Slack and records New Relic deployment markers."

---

## 5. How to Run This Lab

### Prerequisites
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Git](https://git-scm.com/)

### Commands

```bash
# Initialize git (required for GitVersion)
cd cicd-handson-lab
git init
git add .
git commit -m "Initial commit"

# Build locally (simulates CI build job)
.\Build.ps1

# Run tests locally (simulates CI test jobs)
.\Test.ps1

# Run the service locally via Docker (simulates deployment)
.\Start.ps1

# Test the API
curl http://localhost:8080/api/subscriptions

# Stop the service
.\Stop.ps1

# Run tests in containers via batect (matches CI exactly)
.\batect unit-test
.\batect integration-test
.\batect coverage-report
```

### Push to GitHub to see the FULLY AUTOMATED pipeline in action

```bash
# Create a GitHub repository, then:
git remote add origin https://github.com/YOUR_USER/cicd-handson-lab.git
git push -u origin main
```

**This single push triggers the entire pipeline automatically:**

```
Push to main
  │
  ▼
┌─ version (GitVersion) ──────────────────────────────────────┐
│  SemVer generated from git history                           │
└─────────────────────────────────────────────────────────────┘
  │                    │
  ▼                    ▼
┌─ application-build ─┐ ┌─ unit-tests ───────┐ ┌─ integration-tests ┐
│  .NET compile       │ │  xUnit + coverage   │ │  API e2e + coverage│
│  Publish + upload   │ │  Upload artifact    │ │  Upload artifact   │
└─────────────────────┘ └────────────────────┘ └────────────────────┘
  │                    │                    │
  ├────────────────────┴────────────────────┘
  ▼
┌─ localstack-deploy ─────────────────────────────────────────┐
│  Services: localstack (port 4566)                            │
│  Step 1: Create VPC + subnet in LocalStack                  │
│  Step 2: aws cloudformation create-stack                    │
│  Step 3: Wait for CREATE_COMPLETE                           │
│  Step 4: List all stack resources                            │
│  Step 5: Verify ECS Cluster exists                          │
│  Step 6: Verify Task Definition exists                     │
│  Step 7: Verify Log Group exists                            │
│  Step 8: Verify Auto Scaling exists                        │
│  Step 9: Verify EventBridge Rule exists                    │
│  Step 10: Verify Security Group exists                     │
│  Result: ✅ or ❌ summary in job output                     │
└─────────────────────────────────────────────────────────────┘
```

**Every time you push code, GitHub Actions will:**
1. ✅ Compile your .NET application
2. ✅ Run all 6 tests
3. ✅ Spin up LocalStack (AWS mock)
4. ✅ Deploy CloudFormation (ECS, ALB, IAM, Logs, Scaling, EventBridge)
5. ✅ Verify every AWS resource was created
6. ✅ Output pass/fail for each resource

👉 **Go to your repo → Actions tab → watch it run in real time.**

Then make a real change and push again:

```bash
# Create a feature branch
git checkout -b feature/add-email-validation
# Make a change to the controller, commit, push
git push origin feature/add-email-validation

# Open a PR from feature/add-email-validation → main
# The pipeline runs again on the PR (validation only) + on merge (full deploy)
```

---

---

## 6. Infrastructure Provisioning — Testing Deployment Locally

This section covers Phase 2 of your company's pipeline: **Octopus → CloudFormation → AWS resources**. You can test this entirely on your machine using **LocalStack**.

### 6.1 New Files Added

| File | Purpose |
|------|---------|
| `cloudformation/template.yml` | CloudFormation template — ECS, ALB, Route53, auto-scaling, EventBridge |
| `scripts/aws-deploy.ps1` | STS role assumption → SSM reads → CloudFormation create/update |
| `scripts/deploy-dacpac.ps1` | SQL Server container → database deployment |
| `scripts/setup-localstack.ps1` | Starts LocalStack with all required AWS services |
| `scripts/verify-deployment.ps1` | Validates all expected AWS resources were created |

### 6.2 How to Test the Full Deployment (Locally)

```powershell
# Step 1: Start LocalStack (AWS mock in Docker)
.\scripts\setup-localstack.ps1
# → Starts localstack container on port 4566
# → Pre-creates VPC + subnets
# → Outputs available services

# Step 2: Deploy the CloudFormation stack
.\scripts\aws-deploy.ps1 -EnvironmentName test -ImageVersion 1.0.0-test.1
# → Reads template.yml
# → Creates CloudFormation stack "MySubscriptionService-test"
# → Waits for CREATE_COMPLETE
# → Lists all created resources

# Step 3: Verify everything was provisioned
.\scripts\verify-deployment.ps1 -StackName MySubscriptionService-test
# → Checks stack status
# → Verifies every resource exists (ECS, IAM, Logs, Scaling, etc.)
# → Validates specific properties (Fargate, schedule expressions)
# → Pass/Fail summary

# Step 4 (optional): Deploy database
.\scripts\deploy-dacpac.ps1
# → Starts SQL Server in Docker
# → Creates subscription database
```

### 6.3 What verify-deployment Checks

The verification script mirrors what you'd do in production — query AWS APIs and assert the infrastructure is correct:

| Check | What it validates |
|-------|-------------------|
| Stack status | `CREATE_COMPLETE` or `UPDATE_COMPLETE` |
| 14 resource types | ECS Cluster, Task Definitions, Service, LogGroups, IAM Roles, TargetGroup, SecurityGroup, Scaling, EventBridge, Route53 |
| Fargate launch type | Task definition uses `FARGATE` compatibility |
| Log group exists | `/ecs/my-subscription-service/*` |
| Auto scaling target | `ScalableTarget` for ECS service exists |
| EventBridge schedule | Rule has `cron(0 0/2 * * ? *)` expression |

### 6.4 The Flow: CI/CD → Deployment → Verification

```
# Simulate the ENTIRE pipeline from commit to running resources:
git add . && git commit -m "Change subscription logic"
.\Build.ps1                                 # CI: compile
.\Test.ps1                                  # CI: test + coverage
.\scripts\setup-localstack.ps1              # "Octopus provisions AWS"
.\scripts\aws-deploy.ps1 -Env test          # "Octopus deploys stack"
.\scripts\verify-deployment.ps1             # "Verify resources created"
.\scripts\deploy-dacpac.ps1                 # "Deploy database schema"
```

This gives you the exact same feedback loop your company has: **change → build → test → deploy → verify**.

### 6.5 Interview: How Would You Answer...

**Q: "How do you know your infrastructure was actually provisioned correctly?"**

A: "We have a multi-layered verification strategy:
1. **CloudFormation itself** reports stack status — `CREATE_COMPLETE` or `ROLLBACK_COMPLETE`
2. **Post-deployment verification** — our deployment script queries AWS APIs (ECS `DescribeTaskDefinition`, CloudWatch `DescribeLogGroups`, Auto Scaling `DescribeScalableTargets`) to confirm each resource exists and is configured correctly
3. **Health checks** — the ALB target group health check hits `/ping` on the service; if the container isn't responding, the target is marked unhealthy and alerts fire
4. **DeployTrack** records deployment markers in New Relic so we can correlate any incident with the exact deployment that caused it"

**Q: "What if the CloudFormation stack creation fails?"**

A: "CloudFormation is declarative — if a resource fails to create, the stack **automatically rolls back** and deletes any resources it created before the failure. The deployment script detects the failure via `wait stack-create-complete` and fails the Octopus deployment. No partial infrastructure is left behind."

**Q: "How does the deploy script authenticate to AWS?"**

A: "The deploy script assumes an IAM role via STS using `Use-STSRole` with a pre-configured `RoleArn`. This gives it **short-lived credentials** (typically 1 hour) scoped to exactly what the deployment needs. The role is configured with a trust policy that only allows the Octopus service to assume it — CI never has production credentials."

---

## 7. Quick Reference: File → Purpose Mapping

| File | Mirrors company's... | Purpose |
|------|---------------------|---------|
| `.github/workflows/ci-cd-pipeline.yml` | `billing-subscription-service.yaml` | Main CI/CD workflow |
| `GitVersion.yml` | `GitVersion.yml` | Semantic versioning rules |
| `.github/scripts/version.sh` | `.github/scripts/version.sh` | GitVersion → version strings |
| `.github/scripts/auto-approve-pr.sh` | `.github/scripts/auto-approve-pr.sh` | Auto-approve trusted PRs |
| `Dockerfile` | Service `Dockerfile` | Multi-stage container build |
| `.batect/development.yml` | `.batect/development.yml` | Containerised test environment |
| `batect.yml` | `batect.yml` | Batect project root |
| `batect.local.yml` | `batect.local.yml` | Local-only overrides (gitignored) |
| `deploytrack.yaml` | `deploytrack.yaml` | Release governance config |
| `.github/tvm/policy.yaml` | `.github/tvm/policy.yaml` | Token Vending Machine policy |
| `cloudformation/template.yml` | `Billing.Subscription.Service.Template.yml` | CloudFormation — ECS, ALB, R53, auto-scaling, EventBridge |
| `scripts/aws-deploy.ps1` | `AWS-Deploy.ps1` | STS assume → SSM reads → CF create/update |
| `scripts/deploy-dacpac.ps1` | `Deploy-Dacpac-Local.ps1` | SQL Server database deployment |
| `scripts/setup-localstack.ps1` | _(local testing)_ | LocalStack AWS mock bootstrap |
| `scripts/verify-deployment.ps1` | _(local testing)_ | Post-deployment resource validation |
| `Build.ps1` | `Build.ps1` | Local build script |
| `Test.ps1` | `Test.ps1` | Local test script |
| `Start.ps1` | `Start.ps1` | Local Docker run |
| `Stop.ps1` | `Stop.ps1` | Local Docker stop |

---

## 8. Key Interview Vocabulary

| Term | Meaning |
|------|---------|
| **GitVersion** | Tool that derives semantic versions from git history automatically |
| **batect** | Containerised task runner — ensures CI and local dev environments match |
| **Artifactory** | Private package registry for Docker images and NuGet packages |
| **Octopus Deploy** | Release management platform — promotes releases across environments |
| **DeployTrack** | Release governance — CAB checks, Slack notifications, New Relic markers |
| **DACPAC** | SQL Server database schema package — deployed separately from the app |
| **CloudFormation** | AWS IaC tool — provisions ECS, ALB, R53, auto-scaling, etc. |
| **TVM (Token Vending Machine)** | Issues short-lived tokens for secure cross-system auth |
| **CAB** | Change Advisory Board — approves/rejects production changes |
| **Quality Gate** | SonarCloud's pass/fail barrier for code quality |
| **Continuous Deployment** | Every commit to main can go to production automatically |
| **Concurrency group** | Ensures only one pipeline runs per branch at a time |
| **STS Role Assumption** | Short-lived AWS credentials via `sts:AssumeRole` — the deploy script never stores long-lived keys |
| **CloudFormation Rollback** | If stack creation fails, CloudFormation automatically cleans up partial resources |
| **LocalStack** | Local AWS mock — lets you test CloudFormation/ECS/IAM etc. on your machine |
| **SSM Parameter Store** | AWS service for storing config (DB creds, env vars) — read at deploy time |
