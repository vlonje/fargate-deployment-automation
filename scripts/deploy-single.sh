#!/bin/bash

################################################################################
# Deploy Single Stack
#
# This script deploys or updates a single CloudFormation stack.
# Useful for quick updates without redeploying everything.
#
# Usage: ./deploy-single.sh <environment> <component>
#
# Components: ecr, codebuild, security, alb, cluster, task, service
#
# Examples:
#   ./deploy-single.sh staging alb
#   ./deploy-single.sh prod service
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1"
}

################################################################################
# Parse arguments
################################################################################
if [ $# -lt 2 ]; then
    log_error "Usage: $0 <environment> <component>"
    echo ""
    echo "Components:"
    echo "  ecr        - ECR Repository"
    echo "  codebuild  - CodeBuild Project"
    echo "  security   - Security Groups"
    echo "  alb        - Application Load Balancer"
    echo "  cluster    - ECS Cluster"
    echo "  task       - Task Definition"
    echo "  service    - ECS Service"
    echo ""
    echo "Example: $0 staging alb"
    exit 1
fi

ENVIRONMENT=$1
COMPONENT=$2

################################################################################
# Validate inputs
################################################################################
if [[ "$ENVIRONMENT" != "staging" ]] && [[ "$ENVIRONMENT" != "prod" ]]; then
    log_error "Environment must be 'staging' or 'prod'"
    exit 1
fi

# Map component to stack name and template file
case "$COMPONENT" in
    ecr)
        STACK_NAME="ecr"
        TEMPLATE_FILE="1-ecr.yaml"
        ;;
    codebuild)
        STACK_NAME="codebuild"
        TEMPLATE_FILE="2-codebuild.yaml"
        ;;
    security)
        STACK_NAME="security"
        TEMPLATE_FILE="3-security-groups.yaml"
        ;;
    alb)
        STACK_NAME="alb"
        TEMPLATE_FILE="4-load-balancer.yaml"
        ;;
    cluster)
        STACK_NAME="cluster"
        TEMPLATE_FILE="5-ecs-cluster.yaml"
        ;;
    task)
        STACK_NAME="task"
        TEMPLATE_FILE="6-task-definition.yaml"
        ;;
    service)
        STACK_NAME="service"
        TEMPLATE_FILE="7-ecs-service.yaml"
        ;;
    *)
        log_error "Invalid component: $COMPONENT"
        log_info "Valid components: ecr, codebuild, security, alb, cluster, task, service"
        exit 1
        ;;
esac

################################################################################
# Load parameters
################################################################################
PARAMS_FILE="$PROJECT_ROOT/cloudformation/parameters/${ENVIRONMENT}.json"

if [ ! -f "$PARAMS_FILE" ]; then
    log_error "Parameter file not found: $PARAMS_FILE"
    exit 1
fi

STACK_PREFIX=$(jq -r '.StackNamePrefix' "$PARAMS_FILE")
PROJECT_NAME=$(jq -r '.ProjectName' "$PARAMS_FILE")
AWS_REGION=$(aws configure get region || echo "us-east-1")

FULL_STACK_NAME="${STACK_PREFIX}-${ENVIRONMENT}-${STACK_NAME}"
TEMPLATE_PATH="$PROJECT_ROOT/cloudformation/${TEMPLATE_FILE}"

################################################################################
# Deploy stack
################################################################################
echo ""
log_info "===== Deploy Single Stack ====="
echo ""
log_info "Environment:  $ENVIRONMENT"
log_info "Component:    $COMPONENT"
log_info "Stack Name:   $FULL_STACK_NAME"
log_info "Template:     $TEMPLATE_FILE"
echo ""

if [ ! -f "$TEMPLATE_PATH" ]; then
    log_error "Template not found: $TEMPLATE_PATH"
    exit 1
fi

# Validate template
log_info "Validating template..."
if ! aws cloudformation validate-template \
    --template-body "file://$TEMPLATE_PATH" \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "Template validation failed"
    exit 1
fi
log_success "Template is valid"

# Check if stack exists
if aws cloudformation describe-stacks \
    --stack-name "$FULL_STACK_NAME" \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    log_info "Stack exists, updating..."
    OPERATION="update-stack"
    WAIT_CONDITION="stack-update-complete"
else
    log_info "Stack does not exist, creating..."
    OPERATION="create-stack"
    WAIT_CONDITION="stack-create-complete"
fi

# Deploy
log_info "Deploying stack..."

if aws cloudformation "$OPERATION" \
    --stack-name "$FULL_STACK_NAME" \
    --template-body "file://$TEMPLATE_PATH" \
    --parameters "file://$PARAMS_FILE" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION" \
    --tags \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Project,Value="$PROJECT_NAME" \
        Key=ManagedBy,Value=CloudFormation \
    >/dev/null 2>&1; then
    
    log_info "Waiting for stack operation to complete..."
    
    if aws cloudformation wait "$WAIT_CONDITION" \
        --stack-name "$FULL_STACK_NAME" \
        --region "$AWS_REGION"; then
        echo ""
        log_success "Stack deployed successfully!"
        
        # Show outputs
        log_info "Stack outputs:"
        aws cloudformation describe-stacks \
            --stack-name "$FULL_STACK_NAME" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].Outputs' \
            --output table
    else
        log_error "Stack deployment failed"
        exit 1
    fi
else
    # Check if it's "no updates" error
    if aws cloudformation describe-stacks \
        --stack-name "$FULL_STACK_NAME" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "No updates required for this stack"
        exit 0
    else
        log_error "Stack deployment failed"
        exit 1
    fi
fi

echo ""
log_success "Done!"
echo ""