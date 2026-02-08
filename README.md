# Fargate Deployment Automation

A complete, production-ready framework for deploying containerized applications to AWS ECS Fargate with automated builds via CodeBuild.

## 🎯 Overview

This framework provides a **reusable, modular infrastructure-as-code solution** for deploying any Dockerized application to AWS Fargate. It's designed to work with minimal configuration changes across different projects.

### Key Features

- ✅ **Modular Architecture** - 7 separate CloudFormation stacks for maximum flexibility
- ✅ **Multi-Environment** - Supports staging and production environments
- ✅ **Automated Builds** - CodeBuild integration for CI/CD
- ✅ **High Availability** - Auto-configured across multiple AZs
- ✅ **Security Best Practices** - HTTPS support, security groups, IAM roles
- ✅ **Local Validation** - Test everything without AWS credentials
- ✅ **Dynamic Exports** - No naming conflicts when deploying multiple services
- ✅ **Comprehensive Logging** - Debug logging throughout all scripts

### Architecture Components

```
┌─────────────┐
│   GitHub    │ ← Source Code
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  CodeBuild  │ ← Build & Push Docker Image
└──────┬──────┘
       │
       ▼
┌─────────────┐
│     ECR     │ ← Container Registry
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌──────────────┐
│     ALB     │────▶│  ECS Fargate │ ← Running Containers
└─────────────┘     └──────────────┘
```

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Local Testing (No AWS Account)](#local-testing-no-aws-account)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [CloudFormation Stacks](#cloudformation-stacks)
- [Scripts](#scripts)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Contributing](#contributing)

## 🔧 Prerequisites

### Required Tools (for local validation)

- **Python 3.x** - For cfn-lint
- **pip3** - Python package manager
- **cfn-lint** - CloudFormation linter
- **jq** - JSON processor
- **shellcheck** - Bash script linter
- **AWS CLI** - For syntax validation (no credentials needed for validation)

### Python Virtual Environment (Recommended for Ubuntu/Debian)

If you're on Ubuntu/Debian and encounter pip installation errors, use a virtual environment:

```bash
# Install python3-venv if not already installed
sudo apt install python3-venv python3-full -y

# Create a virtual environment in the project directory
cd fargate-deployment-automation
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate

# Your prompt will now show (venv) prefix
# Install packages within the venv
pip install cfn-lint

# Continue with setup
./scripts/setup-local-testing.sh
```

**Note:** When using a virtual environment:
- Always activate it before running validation scripts: `source venv/bin/activate`
- To deactivate: `deactivate`
- The `venv/` directory is already in `.gitignore`

### AWS Resources (for actual deployment)

- **AWS Account** with appropriate permissions
- **VPC** with public and private subnets across multiple AZs
- **Internet Gateway** attached to public subnets
- **NAT Gateway** for private subnets (ECS tasks need to pull images)
- **IAM Roles**:
  - ECS Task Execution Role
  - ECS Task Role
  - CodeBuild Service Role
- **(Optional) ACM Certificate** for HTTPS

## 🚀 Quick Start

### 0. (Optional but Recommended) Set Up Virtual Environment

If you're on Ubuntu/Debian:

```bash
# Install python3-venv
sudo apt install python3-venv python3-full -y

# Create and activate virtual environment
cd fargate-deployment-automation
python3 -m venv venv
source venv/bin/activate

# Install cfn-lint
pip install cfn-lint
```

### 1. Install Local Testing Tools

```bash
# Install validation tools (no AWS account needed)
./scripts/setup-local-testing.sh
```

### 2. Set Up Configuration

```bash
# Copy example parameter files
cp cloudformation/parameters/staging.json.example cloudformation/parameters/staging.json

# Edit with your AWS resource IDs
nano cloudformation/parameters/staging.json
```

### 3. Validate Locally

```bash
# Run comprehensive validation (no AWS credentials needed)
./scripts/validate-all.sh

# Validate with detailed output
./scripts/validate-all.sh --verbose
```

### 4. Deploy (when you have AWS access)

```bash
# Dry-run first (validates without deploying)
./scripts/deploy.sh staging --dry-run

# Deploy for real
./scripts/deploy.sh staging

# Trigger a build
./scripts/build.sh staging
```

## 🧪 Local Testing (No AWS Account)

This framework is designed to be validated **completely offline** before deploying to AWS.

### What You Can Test Locally

- ✅ CloudFormation YAML syntax
- ✅ Parameter file JSON validation
- ✅ Cross-stack reference consistency
- ✅ Bash script syntax and best practices
- ✅ Resource naming conventions
- ✅ Template parameter mappings
- ✅ Logical errors in templates

### Setup Local Testing Environment

**Option 1: With Virtual Environment (Recommended for Ubuntu/Debian)**

```bash
# Install python3-venv
sudo apt install python3-venv python3-full -y

# Create virtual environment
cd fargate-deployment-automation
python3 -m venv venv

# Activate it
source venv/bin/activate

# Install cfn-lint
pip install cfn-lint

# Install other tools
./scripts/setup-local-testing.sh
```

**Option 2: System-Wide Installation**

```bash
# One-time setup (installs all tools)
./scripts/setup-local-testing.sh
```

This installs:
- `cfn-lint` - CloudFormation linter
- `jq` - JSON processor
- `shellcheck` - Bash linter
- `aws-cli` - For syntax validation

### Run Validations

```bash
# Validate everything
./scripts/validate-all.sh

# Show detailed errors
./scripts/validate-all.sh --verbose

# Validate specific component
cfn-lint cloudformation/1-ecr.yaml

# Validate parameter file
jq empty cloudformation/parameters/staging.json

# Validate bash script
shellcheck scripts/deploy.sh
```

### Interpreting Validation Results

```
✓ PASS  - Check passed successfully
⚠ WARN  - Warning (won't prevent deployment but review recommended)
✗ FAIL  - Must be fixed before deployment
```

## 📁 Project Structure

```
fargate-deployment-automation/
├── cloudformation/
│   ├── 1-ecr.yaml                    # ECR Repository
│   ├── 2-codebuild.yaml              # CodeBuild Project
│   ├── 3-security-groups.yaml        # Security Groups (ALB & ECS)
│   ├── 4-load-balancer.yaml          # Application Load Balancer
│   ├── 5-ecs-cluster.yaml            # ECS Cluster (with existence check)
│   ├── 6-task-definition.yaml        # Fargate Task Definition
│   ├── 7-ecs-service.yaml            # ECS Service
│   └── parameters/
│       ├── staging.json.example      # Staging template
│       ├── prod.json.example         # Production template
│       └── README.md                 # Parameter documentation
├── buildspec.yml                     # CodeBuild build specification
├── scripts/
│   ├── setup-local-testing.sh        # Install validation tools
│   ├── validate-all.sh               # Comprehensive validation
│   ├── deploy.sh                     # Deploy all stacks
│   ├── deploy-single.sh              # Deploy single stack
│   ├── build.sh                      # Trigger CodeBuild
│   └── rollback.sh                   # Rollback deployment
├── tests/
│   ├── test-parameters.sh            # Parameter validation tests
│   ├── test-cross-stack-refs.sh      # Cross-stack reference tests
│   └── test-naming-conventions.sh    # Naming convention tests
├── .gitignore
└── README.md                         # This file
```

## ⚙️ Configuration

### Parameter Files

Configuration is managed through JSON parameter files:

- `staging.json.example` / `prod.json.example` - Templates (committed to git)
- `staging.json` / `prod.json` - Your actual config (git-ignored)

**Key Parameters:**

```json
{
  "StackNamePrefix": "vin-app",           // Prefix for all stacks
  "Environment": "staging",               // staging or prod
  "ProjectName": "vin-app",               // Project name
  "GitHubRepo": "https://github.com/...", // Your repository
  "GitHubBranch": "main",                 // Branch to build
  "ContainerPort": "8080",                // App port
  "LoadBalancerScheme": "internet-facing", // Public or internal
  "LoadBalancerProtocol": "HTTPS",        // HTTP or HTTPS
  "DesiredCount": "2",                    // Number of tasks
  "TaskCPU": "512",                       // CPU units
  "TaskMemory": "1024",                   // Memory (MB)
  "VpcId": "vpc-xxxxx",                   // Existing VPC
  "PublicSubnetIds": "subnet-a,subnet-b", // Public subnets
  "PrivateSubnetIds": "subnet-c,subnet-d" // Private subnets
}
```

See [cloudformation/parameters/README.md](cloudformation/parameters/README.md) for complete parameter documentation.

### Stack Naming Convention

All stacks follow this pattern:
```
{StackNamePrefix}-{Environment}-{Component}
```

Examples:
- `vin-app-staging-ecr`
- `vin-app-staging-codebuild`
- `vin-app-staging-alb`
- `vin-app-prod-ecr`
- `another-service-staging-ecr` ← No conflicts!

### Export Naming Convention

All CloudFormation exports use:
```
{StackName}-{ResourceName}
```

Examples:
- `vin-app-staging-ecr-RepositoryUri`
- `vin-app-staging-alb-LoadBalancerDNS`

This **prevents naming conflicts** when deploying multiple services.

## 🚀 Deployment

### Prerequisites Check

Before deploying, ensure you have:

1. ✅ AWS CLI configured with credentials
2. ✅ Valid parameter file (`staging.json` or `prod.json`)
3. ✅ All required AWS resources (VPC, subnets, IAM roles)
4. ✅ Passed local validation (`./scripts/validate-all.sh`)

### Deployment Workflow

#### Option 1: Deploy Everything

```bash
# Dry-run (validates without deploying)
./scripts/deploy.sh staging --dry-run

# Deploy all stacks
./scripts/deploy.sh staging

# For production
./scripts/deploy.sh prod
```

This deploys all 7 stacks in the correct order:
1. ECR Repository
2. CodeBuild Project
3. Security Groups
4. Application Load Balancer
5. ECS Cluster
6. Task Definition
7. ECS Service
8. Triggers initial CodeBuild

#### Option 2: Deploy Individual Stack

```bash
# Deploy only ALB stack
./scripts/deploy-single.sh staging alb

# Deploy only ECS service
./scripts/deploy-single.sh staging service

# Available components:
# ecr, codebuild, security, alb, cluster, task, service
```

### Triggering Builds

After deployment, trigger CodeBuild to build and deploy your application:

```bash
# Trigger build
./scripts/build.sh staging

# Monitor build progress in AWS Console or CLI
aws codebuild batch-get-builds --ids <build-id>
```

### Deployment Order

The framework deploys stacks in dependency order:

```
ECR
 ↓
CodeBuild (imports ECR URI)
 ↓
Security Groups
 ↓
Load Balancer (imports Security Groups)
 ↓
ECS Cluster
 ↓
Task Definition (imports ECR URI)
 ↓
ECS Service (imports Cluster, Task, ALB, Security Groups)
```

## 📦 CloudFormation Stacks

### Stack 1: ECR Repository

**File:** `1-ecr.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-ecr`

Creates an Elastic Container Registry repository for Docker images.

**Features:**
- Image scanning on push
- Lifecycle policy (keeps last 10 images)
- Dynamic exports

**Outputs:**
- `RepositoryArn`
- `RepositoryUri`
- `RepositoryName`

### Stack 2: CodeBuild Project

**File:** `2-codebuild.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-codebuild`

**Status:** 🚧 Coming in Session 2

Creates CodeBuild project for building Docker images.

### Stack 3: Security Groups

**File:** `3-security-groups.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-security`

**Status:** 🚧 Coming in Session 3

Creates security groups for ALB and ECS tasks.

### Stack 4: Application Load Balancer

**File:** `4-load-balancer.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-alb`

**Status:** 🚧 Coming in Session 3

Creates ALB, target group, and listener.

### Stack 5: ECS Cluster

**File:** `5-ecs-cluster.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-cluster`

**Status:** 🚧 Coming in Session 4

Creates ECS cluster with existence check via Lambda custom resource.

### Stack 6: Task Definition

**File:** `6-task-definition.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-task`

**Status:** 🚧 Coming in Session 4

Defines Fargate task with container configuration.

### Stack 7: ECS Service

**File:** `7-ecs-service.yaml`  
**Stack Name:** `{StackNamePrefix}-{Environment}-service`

**Status:** 🚧 Coming in Session 5

Creates ECS service connected to ALB.

## 🔨 Scripts

### setup-local-testing.sh

Installs all tools needed for local validation.

```bash
./scripts/setup-local-testing.sh
```

**Installs:**
- Python 3 & pip
- cfn-lint
- jq
- shellcheck
- AWS CLI

**OS Support:** Ubuntu, CentOS, macOS

### validate-all.sh

Comprehensive validation of all templates, parameters, and scripts.

```bash
# Basic validation
./scripts/validate-all.sh

# Verbose mode (shows detailed errors)
./scripts/validate-all.sh --verbose
```

**Checks:**
- CloudFormation syntax (cfn-lint)
- CloudFormation validation (AWS CLI)
- Parameter file JSON syntax
- Required parameters presence
- Bash script syntax (shellcheck)
- Cross-stack references
- Naming conventions

### deploy.sh

**Status:** 🚧 Coming in Session 5

Deploys all CloudFormation stacks in the correct order.

```bash
# Dry-run mode (validates only)
./scripts/deploy.sh staging --dry-run

# Deploy for real
./scripts/deploy.sh staging
./scripts/deploy.sh prod
```

### deploy-single.sh

**Status:** 🚧 Coming in Session 5

Deploys or updates a single stack.

```bash
./scripts/deploy-single.sh staging ecr
./scripts/deploy-single.sh prod alb
```

### build.sh

**Status:** 🚧 Coming in Session 5

Manually triggers CodeBuild.

```bash
./scripts/build.sh staging
./scripts/build.sh prod
```

### rollback.sh

**Status:** 🚧 Coming in Session 5

Rolls back deployment.

```bash
# Rollback entire deployment
./scripts/rollback.sh staging

# Rollback specific stack
./scripts/rollback.sh staging service
```

## 🔍 Troubleshooting

### Local Validation Issues

**"error: externally-managed-environment" when installing cfn-lint**

This error occurs on newer Ubuntu/Debian systems (Python 3.11+) that use PEP 668. Solution:

```bash
# Use a virtual environment (recommended)
sudo apt install python3-venv python3-full -y
cd fargate-deployment-automation
python3 -m venv venv
source venv/bin/activate
pip install cfn-lint

# Now run the setup script
./scripts/setup-local-testing.sh
```

**"cfn-lint: command not found"**
```bash
# If using virtual environment, make sure it's activated
source venv/bin/activate

# If installed with --user, add to PATH
export PATH="$HOME/.local/bin:$PATH"

# Or run setup script again
./scripts/setup-local-testing.sh
```

**"Parameter validation failed"**
- Check parameter names are exact matches (case-sensitive)
- Verify all required parameters are present
- Validate JSON syntax: `jq empty staging.json`

**"Cross-stack reference errors"**
- Ensure export names match import values
- Stack names must be consistent
- Check that dependency stacks exist

### Deployment Issues

**(To be added in Session 5)**

## 📚 Advanced Topics

### HTTPS Setup

To use HTTPS with your load balancer:

1. **Create ACM Certificate:**
   ```bash
   aws acm request-certificate \
     --domain-name example.com \
     --validation-method DNS \
     --region us-east-1
   ```

2. **Validate certificate** (follow AWS Console instructions for DNS validation)

3. **Update parameter file:**
   ```json
   {
     "LoadBalancerProtocol": "HTTPS",
     "SSLCertificateArn": "arn:aws:acm:us-east-1:123:certificate/xxx"
   }
   ```

### Private GitHub Repositories

For private repositories, you need to set up GitHub authentication:

**Option 1: GitHub Personal Access Token (Classic)**

1. Generate token in GitHub: Settings → Developer settings → Personal access tokens
2. Required scopes: `repo` (full control)
3. Store in AWS Secrets Manager:
   ```bash
   aws secretsmanager create-secret \
     --name github-token \
     --secret-string "ghp_xxxxxxxxxxxx"
   ```
4. Update CodeBuild template to use secret (see Session 2)

**Option 2: AWS CodeStar Connection**

1. Create GitHub connection in AWS Console
2. Authorize with GitHub OAuth
3. Use connection ARN in CodeBuild configuration

### Multiple Services in Same VPC

You can deploy multiple independent services using this framework:

```bash
# Service 1
export STACK_PREFIX="api-service"
./scripts/deploy.sh staging

# Service 2
export STACK_PREFIX="web-app"
./scripts/deploy.sh staging
```

Each service gets unique stack names and exports (no conflicts).

### Auto-Scaling

**(To be added in future enhancement)**

## 🤝 Contributing

This framework is designed to be extended. Some ideas:

- [ ] Auto-scaling policies
- [ ] CloudWatch alarms and dashboards
- [ ] Blue/green deployments
- [ ] Canary deployments
- [ ] WAF integration
- [ ] VPC Flow Logs
- [ ] X-Ray tracing

## 📝 License

MIT License - feel free to use and modify for your projects.

## 🆘 Support

For issues, questions, or contributions:
1. Check existing GitHub issues
2. Review troubleshooting section
3. Open a new issue with details

---

## Current Status

### ✅ Completed (Session 1)
- Project structure
- Local testing setup (`setup-local-testing.sh`)
- Comprehensive validation (`validate-all.sh`)
- ECR CloudFormation template
- Parameter file templates
- Documentation

### 🚧 In Progress
- Session 2: CodeBuild template & buildspec.yml
- Session 3: Security Groups & Load Balancer
- Session 4: ECS Cluster & Task Definition
- Session 5: ECS Service & deployment scripts

---

**Last Updated:** Session 1 Complete  
**Framework Version:** 1.0.0-dev  
**AWS Services:** ECS Fargate, ECR, CodeBuild, ALB, VPC