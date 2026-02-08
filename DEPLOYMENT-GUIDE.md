# Deployment Guide

Complete step-by-step guide for deploying your application using the Fargate Deployment Automation framework.

## Prerequisites Checklist

Before deploying, ensure you have:

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] VPC with public and private subnets (at least 2 AZs)
- [ ] Internet Gateway attached to public subnets
- [ ] NAT Gateway in private subnets
- [ ] GitHub repository with your application code
- [ ] Dockerfile in your repository
- [ ] Parameter files configured (staging.json, prod.json)

## Step 1: Create IAM Roles

### CodeBuild Service Role

```bash
chmod +x scripts/create-codebuild-role.sh
./scripts/create-codebuild-role.sh
```

Copy the ARN output and add to your parameter files as `CodeBuildServiceRoleArn`.

### ECS Task Roles

```bash
chmod +x scripts/create-ecs-roles.sh
./scripts/create-ecs-roles.sh
```

Copy the two ARNs output and add to your parameter files:
- `ECSTaskExecutionRoleArn`
- `ECSTaskRoleArn`

## Step 2: Configure Parameters

### Copy Example Files

```bash
cp cloudformation/parameters/staging.json.example cloudformation/parameters/staging.json
cp cloudformation/parameters/prod.json.example cloudformation/parameters/prod.json
```

### Edit Parameter Files

Edit `staging.json` and `prod.json` with your actual values:

**Required Parameters:**
```json
{
  "StackNamePrefix": "your-app-name",
  "Environment": "staging",
  "ProjectName": "your-app-name",
  "GitHubRepo": "https://github.com/your-username/your-repo",
  "GitHubBranch": "main",
  "DockerfilePath": "./Dockerfile",
  "ContainerPort": "8080",
  "HealthCheckPath": "/health",
  "LoadBalancerScheme": "internet-facing",
  "LoadBalancerProtocol": "HTTP",
  "SSLCertificateArn": "",
  "DesiredCount": "1",
  "TaskCPU": "256",
  "TaskMemory": "512",
  "VpcId": "vpc-xxxxx",
  "PublicSubnetIds": "subnet-xxx,subnet-yyy",
  "PrivateSubnetIds": "subnet-aaa,subnet-bbb",
  "ECSTaskExecutionRoleArn": "arn:aws:iam::...",
  "ECSTaskRoleArn": "arn:aws:iam::...",
  "CodeBuildServiceRoleArn": "arn:aws:iam::..."
}
```

### Find Your AWS Resource IDs

**VPC and Subnets:**
```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table

# List Subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

## Step 3: Validate Configuration

Before deploying, validate everything:

```bash
# Validate templates and parameters
./scripts/validate-all.sh

# Dry-run deployment (validates without deploying)
./scripts/deploy.sh staging --dry-run
```

## Step 4: Deploy Infrastructure

### Full Deployment

Deploy all stacks for the first time:

```bash
./scripts/deploy.sh staging
```

This will:
1. Deploy ECR repository
2. Deploy CodeBuild project
3. Deploy security groups
4. Deploy Application Load Balancer
5. Deploy ECS cluster
6. Deploy task definition
7. Deploy ECS service
8. Trigger initial CodeBuild

**Deployment takes approximately 10-15 minutes.**

### Monitor Deployment

Watch the deployment progress:

```bash
# Check CloudFormation stack status
aws cloudformation describe-stacks \
  --stack-name your-app-staging-service \
  --query 'Stacks[0].StackStatus' \
  --output text

# Check CodeBuild status
aws codebuild list-builds-for-project \
  --project-name your-app-staging-build \
  --query 'ids[0]' \
  --output text
```

## Step 5: Verify Deployment

### Check ECS Service

```bash
# Check service status
aws ecs describe-services \
  --cluster your-app-staging-cluster \
  --services your-app-staging-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table
```

### Check Application Load Balancer

```bash
# Get ALB URL
aws cloudformation describe-stacks \
  --stack-name your-app-staging-alb \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text
```

### Test Your Application

```bash
# Test health endpoint
ALB_URL=$(aws cloudformation describe-stacks \
  --stack-name your-app-staging-alb \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

curl $ALB_URL/health
```

## Step 6: Subsequent Deployments

### Update Application Code

After pushing new code to GitHub:

```bash
# Trigger new build
./scripts/build.sh staging

# Monitor build progress
# Build will automatically deploy to ECS when complete
```

### Update Infrastructure

Update a single stack:

```bash
# Update task definition (change CPU/Memory)
./scripts/deploy-single.sh staging task

# Update service (change desired count)
./scripts/deploy-single.sh staging service

# Update load balancer configuration
./scripts/deploy-single.sh staging alb
```

## Common Deployment Scenarios

### Scenario 1: Change Container Resources

1. Edit `staging.json`:
   ```json
   {
     "TaskCPU": "512",
     "TaskMemory": "1024"
   }
   ```

2. Update task definition:
   ```bash
   ./scripts/deploy-single.sh staging task
   ```

3. Force new deployment:
   ```bash
   ./scripts/build.sh staging
   ```

### Scenario 2: Scale Up/Down

1. Edit `staging.json`:
   ```json
   {
     "DesiredCount": "3"
   }
   ```

2. Update service:
   ```bash
   ./scripts/deploy-single.sh staging service
   ```

### Scenario 3: Enable HTTPS

1. Create ACM certificate:
   ```bash
   aws acm request-certificate \
     --domain-name example.com \
     --validation-method DNS \
     --region us-east-1
   ```

2. Validate certificate (follow AWS Console instructions)

3. Edit `staging.json`:
   ```json
   {
     "LoadBalancerProtocol": "HTTPS",
     "SSLCertificateArn": "arn:aws:acm:region:account:certificate/xxx"
   }
   ```

4. Update ALB:
   ```bash
   ./scripts/deploy-single.sh staging alb
   ```

### Scenario 4: Switch to Internal Load Balancer

1. Edit `staging.json`:
   ```json
   {
     "LoadBalancerScheme": "internal"
   }
   ```

2. Redeploy security groups and ALB:
   ```bash
   ./scripts/deploy-single.sh staging security
   ./scripts/deploy-single.sh staging alb
   ```

## Rollback Procedures

### Rollback to Previous Task Definition

```bash
./scripts/rollback.sh staging --service
# Follow prompts to select previous revision
```

### Delete Single Stack

```bash
./scripts/rollback.sh staging --delete alb
```

### Delete All Infrastructure

```bash
./scripts/rollback.sh staging --delete-all
# Type 'DELETE' to confirm
```

## Troubleshooting

### Build Fails

**Check build logs:**
```bash
# Get latest build ID
BUILD_ID=$(aws codebuild list-builds-for-project \
  --project-name your-app-staging-build \
  --query 'ids[0]' \
  --output text)

# Get logs
aws codebuild batch-get-builds --ids $BUILD_ID
```

**Common issues:**
- Dockerfile not found → Check `DockerfilePath` parameter
- ECR login failed → Check CodeBuild IAM role permissions
- Build timeout → Increase timeout in CodeBuild template

### Service Won't Start

**Check task status:**
```bash
aws ecs list-tasks \
  --cluster your-app-staging-cluster \
  --service-name your-app-staging-service

# Get task details
aws ecs describe-tasks \
  --cluster your-app-staging-cluster \
  --tasks task-id
```

**Common issues:**
- Health check failing → Verify `/health` endpoint returns 200
- Task stopped → Check CloudWatch Logs for errors
- Image pull failed → Verify ECR permissions

### Health Check Failing

**Verify health endpoint:**
```bash
# SSH into task (if enabled)
aws ecs execute-command \
  --cluster your-app-staging-cluster \
  --task task-id \
  --container your-app-staging-container \
  --interactive \
  --command "/bin/sh"

# Test health endpoint
curl localhost:8080/health
```

### Can't Access Application

**Check security groups:**
```bash
# Verify ALB security group allows inbound traffic
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=your-app-staging-alb-sg"
```

**Check target health:**
```bash
# Get target group ARN
TG_ARN=$(aws cloudformation describe-stacks \
  --stack-name your-app-staging-alb \
  --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' \
  --output text)

# Check target health
aws elbv2 describe-target-health --target-group-arn $TG_ARN
```

## Production Deployment

Before deploying to production:

1. **Test in staging thoroughly**
2. **Configure HTTPS** (required for production)
3. **Use at least 2 tasks** (high availability)
4. **Set up monitoring** (CloudWatch alarms)
5. **Configure auto-scaling** (already included)
6. **Use separate AWS account** (recommended)

```bash
# Deploy to production
./scripts/deploy.sh prod

# Monitor carefully
watch -n 5 'aws ecs describe-services \
  --cluster your-app-prod-cluster \
  --services your-app-prod-service \
  --query "services[0].deployments" \
  --output table'
```

## Monitoring & Maintenance

### CloudWatch Logs

```bash
# View application logs
aws logs tail /ecs/your-app-staging --follow
```

### Metrics

- ECS Service: CPU, Memory, Task count
- ALB: Request count, Target response time
- CodeBuild: Build success/failure rate

### Cost Optimization

1. Use Fargate Spot for dev/staging
2. Right-size task CPU/memory
3. Set appropriate log retention (default: 7 days)
4. Delete unused images from ECR

## Next Steps

- Set up CloudWatch alarms
- Configure auto-scaling policies
- Set up CI/CD pipeline (GitHub Actions, etc.)
- Add custom domain with Route 53
- Enable WAF for security
- Set up VPC Flow Logs

---

**Questions or Issues?** Check the main [README.md](../README.md) for more information.