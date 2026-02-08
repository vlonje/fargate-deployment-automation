#!/bin/bash

################################################################################
# Deploy All Stacks - Main Deployment Script
#
# This script deploys all CloudFormation stacks for Fargate deployment
# in the correct dependency order.
#
# Usage: ./deploy.sh <environment> [--dry-run]
#
# Examples:
#   ./deploy.sh staging
#   ./deploy.sh prod --dry-run
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Debug logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

################################################################################
# Parse arguments
################################################################################
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <environment> [--dry-run]"
    log_info "Example: $0 staging"
    log_info "Example: $0 prod --dry-run"
    exit 1
fi

ENVIRONMENT=$1
DRY_RUN=false

if [[ "$2" == "--dry-run" ]] || [[ "$2" == "--validate" ]]; then
    DRY_RUN=true
    log_warning "Running in DRY-RUN mode - no resources will be deployed"
fi

################################################################################
# Validate environment
################################################################################
if [[ "$ENVIRONMENT" != "staging" ]] && [[ "$ENVIRONMENT" != "prod" ]]; then
    log_error "Environment must be 'staging' or 'prod'"
    exit 1
fi

################################################################################
# Load parameters
################################################################################
PARAMS_FILE="$PROJECT_ROOT/cloudformation/parameters/${ENVIRONMENT}.json"

if [ ! -f "$PARAMS_FILE" ]; then
    log_error "Parameter file not found: $PARAMS_FILE"
    log_info "Create it from the example: cp ${PARAMS_FILE}.example $PARAMS_FILE"
    exit 1
fi

log_info "Loading parameters from: $PARAMS_FILE"

# Extract key parameters
STACK_PREFIX=$(jq -r '.StackNamePrefix' "$PARAMS_FILE")
PROJECT_NAME=$(jq -r '.ProjectName' "$PARAMS_FILE")
AWS_REGION=$(aws configure get region || echo "us-east-1")

log_info "Stack Prefix: $STACK_PREFIX"
log_info "Environment:  $ENVIRONMENT"
log_info "Project:      $PROJECT_NAME"
log_info "Region:       $AWS_REGION"

################################################################################
# Check prerequisites
################################################################################
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing=()
    
    if ! command -v aws >/dev/null 2>&1; then
        missing+=("aws-cli")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

################################################################################
# Deploy a single stack
################################################################################
deploy_stack() {
    local stack_number=$1
    local stack_name=$2
    local template_file=$3
    
    local full_stack_name="${STACK_PREFIX}-${ENVIRONMENT}-${stack_name}"
    local template_path="$PROJECT_ROOT/cloudformation/${template_file}"
    
    log_section "Stack ${stack_number}/7: ${stack_name}"
    
    if [ ! -f "$template_path" ]; then
        log_error "Template not found: $template_path"
        return 1
    fi
    
    log_info "Stack Name: $full_stack_name"
    log_info "Template:   $template_file"
    
    if $DRY_RUN; then
        log_info "DRY-RUN: Validating template only..."
        if aws cloudformation validate-template \
            --template-body "file://$template_path" \
            --region "$AWS_REGION" >/dev/null 2>&1; then
            log_success "Template validation passed"
        else
            log_error "Template validation failed"
            return 1
        fi
        return 0
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks \
        --stack-name "$full_stack_name" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Stack exists, updating..."
        OPERATION="update-stack"
    else
        log_info "Stack does not exist, creating..."
        OPERATION="create-stack"
    fi
    
    # Deploy stack
    log_info "Deploying stack..."
    
    if aws cloudformation "$OPERATION" \
        --stack-name "$full_stack_name" \
        --template-body "file://$template_path" \
        --parameters "file://$PARAMS_FILE" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --tags \
            Key=Environment,Value="$ENVIRONMENT" \
            Key=Project,Value="$PROJECT_NAME" \
            Key=ManagedBy,Value=CloudFormation \
        >/dev/null 2>&1; then
        
        log_info "Waiting for stack operation to complete..."
        
        if [ "$OPERATION" == "create-stack" ]; then
            WAIT_CONDITION="stack-create-complete"
        else
            WAIT_CONDITION="stack-update-complete"
        fi
        
        if aws cloudformation wait "$WAIT_CONDITION" \
            --stack-name "$full_stack_name" \
            --region "$AWS_REGION" 2>&1; then
            log_success "Stack deployed successfully"
        else
            log_error "Stack deployment failed"
            return 1
        fi
    else
        # Check if it's "no updates" error
        if aws cloudformation describe-stacks \
            --stack-name "$full_stack_name" \
            --region "$AWS_REGION" >/dev/null 2>&1; then
            log_info "No updates required for this stack"
            return 0
        else
            log_error "Stack deployment failed"
            return 1
        fi
    fi
}

################################################################################
# Main deployment flow
################################################################################
main() {
    echo ""
    log_info "===== Fargate Deployment Automation ====="
    echo ""
    
    check_prerequisites
    
    # Deploy stacks in order
    deploy_stack 1 "ecr" "1-ecr.yaml" || exit 1
    deploy_stack 2 "codebuild" "2-codebuild.yaml" || exit 1
    deploy_stack 3 "security" "3-security-groups.yaml" || exit 1
    deploy_stack 4 "alb" "4-load-balancer.yaml" || exit 1
    deploy_stack 5 "cluster" "5-ecs-cluster.yaml" || exit 1
    deploy_stack 6 "task" "6-task-definition.yaml" || exit 1
    deploy_stack 7 "service" "7-ecs-service.yaml" || exit 1
    
    if $DRY_RUN; then
        log_section "Dry-Run Complete"
        log_success "All templates validated successfully"
        log_info "Run without --dry-run to deploy"
        exit 0
    fi
    
    # Trigger initial build
    log_section "Triggering Initial Build"
    log_info "Starting CodeBuild to build and deploy Docker image..."
    
    BUILD_PROJECT="${STACK_PREFIX}-${ENVIRONMENT}-build"
    
    if BUILD_ID=$(aws codebuild start-build \
        --project-name "$BUILD_PROJECT" \
        --region "$AWS_REGION" \
        --query 'build.id' \
        --output text 2>/dev/null); then
        log_success "Build started: $BUILD_ID"
        log_info "Monitor build: aws codebuild batch-get-builds --ids $BUILD_ID"
    else
        log_warning "Could not trigger initial build"
        log_info "Trigger manually: ./scripts/build.sh $ENVIRONMENT"
    fi
    
    # Summary
    log_section "Deployment Complete!"
    
    ALB_URL=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-${ENVIRONMENT}-alb" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
        --output text 2>/dev/null || echo "Unable to retrieve")
    
    echo ""
    log_success "All stacks deployed successfully!"
    echo ""
    echo "Application URL: $ALB_URL"
    echo ""
    log_info "Next steps:"
    log_info "  1. Wait for CodeBuild to complete"
    log_info "  2. Check service health in ECS console"
    log_info "  3. Access your application at: $ALB_URL"
    echo ""
}

main