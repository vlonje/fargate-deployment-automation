#!/bin/bash

################################################################################
# Create ECS IAM Roles
#
# This script creates the IAM roles required by ECS tasks:
# 1. ECS Task Execution Role - Used by ECS to pull images and write logs
# 2. ECS Task Role - Used by your application for AWS API calls
#
# Usage: ./scripts/create-ecs-roles.sh
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

################################################################################
# Create ECS Task Execution Role
################################################################################
create_task_execution_role() {
    local role_name="ecsTaskExecutionRole"
    
    log_info "Creating ECS Task Execution Role: $role_name"
    
    # Trust policy
    cat > /tmp/ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    if aws iam create-role \
      --role-name "$role_name" \
      --assume-role-policy-document file:///tmp/ecs-task-execution-trust-policy.json \
      --description "ECS Task Execution Role - allows ECS to pull images and write logs" \
      >/dev/null 2>&1; then
      log_success "Role created: $role_name"
    else
      log_info "Role may already exist, continuing..."
    fi
    
    # Attach AWS managed policy
    log_info "Attaching AmazonECSTaskExecutionRolePolicy..."
    if aws iam attach-role-policy \
      --role-name "$role_name" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
      >/dev/null 2>&1; then
      log_success "Policy attached"
    else
      log_info "Policy may already be attached"
    fi
    
    # Get ARN
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
    echo "$role_arn"
}

################################################################################
# Create ECS Task Role
################################################################################
create_task_role() {
    local role_name="ecsTaskRole"
    
    log_info "Creating ECS Task Role: $role_name"
    
    # Trust policy
    cat > /tmp/ecs-task-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    if aws iam create-role \
      --role-name "$role_name" \
      --assume-role-policy-document file:///tmp/ecs-task-trust-policy.json \
      --description "ECS Task Role - permissions for the application running in the container" \
      >/dev/null 2>&1; then
      log_success "Role created: $role_name"
    else
      log_info "Role may already exist, continuing..."
    fi
    
    # Create basic policy for task role
    local policy_name="${role_name}-policy"
    
    cat > /tmp/ecs-task-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBasicOperations",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Get account ID
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
    
    # Create policy
    if aws iam create-policy \
      --policy-name "$policy_name" \
      --policy-document file:///tmp/ecs-task-policy.json \
      >/dev/null 2>&1; then
      log_success "Policy created: $policy_name"
    else
      log_info "Policy may already exist, using existing..."
    fi
    
    # Attach policy to role
    if aws iam attach-role-policy \
      --role-name "$role_name" \
      --policy-arn "$policy_arn" \
      >/dev/null 2>&1; then
      log_success "Policy attached to role"
    else
      log_info "Policy may already be attached"
    fi
    
    # Get ARN
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
    echo "$role_arn"
}

################################################################################
# Main
################################################################################
main() {
    echo ""
    log_info "===== Creating ECS IAM Roles ====="
    echo ""
    
    # Create Task Execution Role
    execution_role_arn=$(create_task_execution_role)
    echo ""
    
    # Create Task Role
    task_role_arn=$(create_task_role)
    echo ""
    
    # Cleanup temp files
    rm -f /tmp/ecs-task-execution-trust-policy.json
    rm -f /tmp/ecs-task-trust-policy.json
    rm -f /tmp/ecs-task-policy.json
    
    # Summary
    log_success "All ECS IAM roles are ready!"
    echo ""
    echo "=========================================="
    echo "Add these ARNs to your parameter files:"
    echo "=========================================="
    echo ""
    echo "ECSTaskExecutionRoleArn: $execution_role_arn"
    echo "ECSTaskRoleArn:          $task_role_arn"
    echo ""
    log_info "Update staging.json and prod.json with these values"
    echo ""
}

main