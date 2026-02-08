# CloudFormation Parameters

This directory contains environment-specific configuration for deploying the Fargate automation framework.

## Quick Start

1. **Copy the example files:**
   ```bash
   cp staging.json.example staging.json
   cp prod.json.example prod.json
   ```

2. **Edit the files** with your actual AWS resource IDs and configuration

3. **Never commit** `staging.json` or `prod.json` to version control (they're in `.gitignore`)

## Parameter Files

### staging.json.example / prod.json.example
Template files with documentation for each parameter. Keep these in version control as templates for team members.

### staging.json / prod.json (you create these)
Your actual configuration files with real AWS resource IDs. These are git-ignored and should never be committed.

## Required Parameters

### Stack Configuration
| Parameter | Description | Example |
|-----------|-------------|---------|
| `StackNamePrefix` | Prefix for all stack names | `vin-app` |
| `Environment` | Environment name | `staging` or `prod` |
| `ProjectName` | Project/app name | `vin-app` |

### GitHub Configuration
| Parameter | Description | Example |
|-----------|-------------|---------|
| `GitHubRepo` | Full GitHub repository URL | `https://github.com/user/repo` |
| `GitHubBranch` | Branch to build from | `main` |
| `DockerfilePath` | Path to Dockerfile in repo | `./Dockerfile` |

### Application Configuration
| Parameter | Description | Example |
|-----------|-------------|---------|
| `ContainerPort` | Port your app listens on | `8080` |
| `HealthCheckPath` | Health check endpoint | `/health` |

### Load Balancer Configuration
| Parameter | Description | Values |
|-----------|-------------|--------|
| `LoadBalancerScheme` | Public or private | `internet-facing` or `internal` |
| `LoadBalancerProtocol` | HTTP or HTTPS | `HTTP` or `HTTPS` |
| `SSLCertificateArn` | ACM cert ARN (for HTTPS) | `arn:aws:acm:...` |

### Fargate Task Configuration
| Parameter | Description | Values |
|-----------|-------------|--------|
| `DesiredCount` | Number of tasks | `1` (staging), `2+` (prod) |
| `TaskCPU` | CPU units | `256`, `512`, `1024`, `2048`, `4096` |
| `TaskMemory` | Memory in MB | `512`, `1024`, `2048`, `4096`, `8192` |

**CPU/Memory Compatibility:**
- CPU 256: Memory 512, 1024, 2048
- CPU 512: Memory 1024, 2048, 3072, 4096
- CPU 1024: Memory 2048, 3072, 4096, 5120, 6144, 7168, 8192
- CPU 2048: Memory 4096-16384 (in 1GB increments)
- CPU 4096: Memory 8192-30720 (in 1GB increments)

### Network Configuration
| Parameter | Description | Example |
|-----------|-------------|---------|
| `VpcId` | Existing VPC ID | `vpc-0123456789abcdef0` |
| `PublicSubnetIds` | Public subnets (comma-separated) | `subnet-abc,subnet-def` |
| `PrivateSubnetIds` | Private subnets (comma-separated) | `subnet-123,subnet-456` |

**Important:**
- Use at least 2 subnets in different Availability Zones for high availability
- Public subnets need Internet Gateway route
- Private subnets need NAT Gateway route (for pulling Docker images from ECR)

### IAM Configuration
| Parameter | Description | Example |
|-----------|-------------|---------|
| `ECSTaskExecutionRoleArn` | Role for ECS to pull images/logs | `arn:aws:iam::123:role/ecsTaskExecutionRole` |
| `ECSTaskRoleArn` | Role for your application | `arn:aws:iam::123:role/myAppRole` |
| `CodeBuildServiceRoleArn` | Role for CodeBuild | `arn:aws:iam::123:role/codebuildRole` |

## Finding AWS Resource IDs

### VPC and Subnets
```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table

# List Subnets for a VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### IAM Roles
```bash
# List IAM roles
aws iam list-roles --query 'Roles[*].[RoleName,Arn]' --output table

# Get specific role ARN
aws iam get-role --role-name ecsTaskExecutionRole --query 'Role.Arn' --output text
```

### ACM Certificates (for HTTPS)
```bash
# List certificates
aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[*].[DomainName,CertificateArn]' --output table
```

## Setting Up IAM Roles

If you don't have the required IAM roles, here's how to create them:

### ECS Task Execution Role
```bash
# Create role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach AWS managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### CodeBuild Service Role
```bash
# Create role
aws iam create-role \
  --role-name codebuild-service-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "codebuild.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Create and attach inline policy (you'll need to customize this)
# See main README.md for full policy document
```

## Environment-Specific Best Practices

### Staging
- ✓ Use 1 task (cost savings)
- ✓ Smaller CPU/memory (256/512)
- ✓ HTTP is acceptable (if not handling sensitive data)
- ✓ Can use same VPC as dev (with different subnets)

### Production
- ✓ Use at least 2 tasks across multiple AZs
- ✓ Larger CPU/memory based on load testing
- ✓ **Always use HTTPS** with valid certificate
- ✓ Separate VPC from staging/dev
- ✓ Enable auto-scaling (future enhancement)
- ✓ Set up CloudWatch alarms

## Validation

Before deploying, validate your parameter files:

```bash
# Validate JSON syntax
jq empty cloudformation/parameters/staging.json

# Run full validation
./scripts/validate-all.sh
```

## Security Best Practices

1. **Never commit actual parameter files** - they may contain sensitive info
2. **Use different AWS accounts** for staging and prod (recommended)
3. **Rotate credentials** regularly if using GitHub tokens
4. **Use least-privilege IAM roles** - only grant necessary permissions
5. **Enable CloudTrail** to audit all API calls
6. **Use AWS Secrets Manager** for sensitive values in production

## Troubleshooting

### "Parameter validation failed"
- Check parameter names match the template exactly (case-sensitive)
- Ensure all required parameters are present
- Verify ARNs are in correct format

### "Invalid subnet for VPC"
- Subnet must belong to the specified VPC
- Verify subnet IDs are correct

### "Certificate not found"
- ACM certificate must be in the same region as your deployment
- Certificate must be validated and issued

## Next Steps

After configuring parameters:
1. Run validation: `./scripts/validate-all.sh`
2. Deploy infrastructure: `./scripts/deploy.sh staging --dry-run`
3. Review the plan
4. Deploy for real: `./scripts/deploy.sh staging`

For more information, see the main [README.md](../../README.md)