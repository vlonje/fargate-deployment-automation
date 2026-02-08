#!/bin/bash

################################################################################
# Create CodeBuild Service Role
#
# This script creates the IAM role required by CodeBuild with all necessary
# permissions for building Docker images and deploying to ECS.
#
# Usage: ./scripts/create-codebuild-role.sh [role-name]
################################################################################

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Role name (default or from argument)
ROLE_NAME="${1:-codebuild-service-role}"

log_info "Creating CodeBuild service role: $ROLE_NAME"
echo ""

################################################################################
# Create Trust Policy
################################################################################
log_info "Creating trust policy..."

cat > /tmp/codebuild-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

################################################################################
# Create IAM Role
################################################################################
log_info "Creating IAM role..."

if aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/codebuild-trust-policy.json \
  --description "Service role for CodeBuild to build Docker images and deploy to ECS" \
  >/dev/null 2>&1; then
  log_success "IAM role created: $ROLE_NAME"
else
  log_error "Failed to create role (it may already exist)"
  log_info "Continuing with existing role..."
fi

echo ""

################################################################################
# Create and Attach Policy
################################################################################
log_info "Creating IAM policy..."

POLICY_NAME="${ROLE_NAME}-policy"

cat > /tmp/codebuild-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogsPermissions",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:*:*:log-group:/aws/codebuild/*"
      ]
    },
    {
      "Sid": "ECRPermissions",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSPermissions",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Permissions",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::codepipeline-*/*"
      ]
    }
  ]
}
EOF

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create policy
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document file:///tmp/codebuild-policy.json \
  >/dev/null 2>&1; then
  log_success "IAM policy created: $POLICY_NAME"
else
  log_info "Policy may already exist, using existing policy..."
fi

echo ""

################################################################################
# Attach Policy to Role
################################################################################
log_info "Attaching policy to role..."

if aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" \
  >/dev/null 2>&1; then
  log_success "Policy attached to role"
else
  log_info "Policy may already be attached"
fi

echo ""

################################################################################
# Get Role ARN
################################################################################
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

log_success "CodeBuild service role is ready!"
echo ""
echo "Role Name: $ROLE_NAME"
echo "Role ARN:  $ROLE_ARN"
echo ""
log_info "Use this ARN in your CloudFormation parameters:"
log_info "  CodeBuildServiceRoleArn: $ROLE_ARN"
echo ""

# Cleanup
rm -f /tmp/codebuild-trust-policy.json /tmp/codebuild-policy.json

log_success "Done!"