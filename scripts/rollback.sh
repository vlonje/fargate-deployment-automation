#!/bin/bash

################################################################################
# Rollback Deployment
#
# This script provides rollback options:
# 1. Rollback ECS service to previous task definition
# 2. Delete all stacks (cleanup)
# 3. Delete a single stack
#
# Usage: ./rollback.sh <environment> [options]
#
# Examples:
#   ./rollback.sh staging --service      # Rollback ECS service
#   ./rollback.sh staging --delete-all   # Delete all stacks
#   ./rollback.sh staging --delete alb   # Delete ALB stack only
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

log_warning() {
    echo -e "${YELLOW}[⚠ WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1"
}

################################################################################
# Parse arguments
################################################################################
if [ $# -lt 2 ]; then
    log_error "Usage: $0 <environment> <action>"
    echo ""
    echo "Actions:"
    echo "  --service            Rollback ECS service to previous task definition"
    echo "  --delete-all         Delete all CloudFormation stacks"
    echo "  --delete <component> Delete a specific stack"
    echo ""
    echo "Examples:"
    echo "  $0 staging --service"
    echo "  $0 prod --delete-all"
    echo "  $0 staging --delete alb"
    exit 1
fi

ENVIRONMENT=$1
ACTION=$2
COMPONENT=$3

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
    exit 1
fi

STACK_PREFIX=$(jq -r '.StackNamePrefix' "$PARAMS_FILE")
AWS_REGION=$(aws configure get region || echo "us-east-1")

################################################################################
# Rollback ECS service to previous task definition
################################################################################
rollback_service() {
    log_info "===== Rollback ECS Service ====="
    echo ""
    
    local service_name="${STACK_PREFIX}-${ENVIRONMENT}-service"
    local cluster_name="${STACK_PREFIX}-${ENVIRONMENT}-cluster"
    local task_family="${STACK_PREFIX}-${ENVIRONMENT}"
    
    log_info "Service:  $service_name"
    log_info "Cluster:  $cluster_name"
    echo ""
    
    # Get current task definition
    log_info "Getting current task definition..."
    local current_task_def=$(aws ecs describe-services \
        --cluster "$cluster_name" \
        --services "$service_name" \
        --region "$AWS_REGION" \
        --query 'services[0].taskDefinition' \
        --output text)
    
    log_info "Current task definition: $current_task_def"
    
    # List recent task definitions
    log_info "Recent task definitions:"
    aws ecs list-task-definitions \
        --family-prefix "$task_family" \
        --region "$AWS_REGION" \
        --sort DESC \
        --max-items 5 \
        --query 'taskDefinitionArns' \
        --output table
    
    echo ""
    read -p "Enter the task definition revision to rollback to (e.g., 3): " -r revision
    
    if [[ ! "$revision" =~ ^[0-9]+$ ]]; then
        log_error "Invalid revision number"
        exit 1
    fi
    
    local target_task_def="arn:aws:ecs:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):task-definition/${task_family}:${revision}"
    
    log_warning "Rolling back service to: $target_task_def"
    read -p "Are you sure? (yes/no) " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi
    
    log_info "Updating service..."
    if aws ecs update-service \
        --cluster "$cluster_name" \
        --service "$service_name" \
        --task-definition "$target_task_def" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "Service rollback initiated"
        log_info "Monitor the deployment in ECS console"
    else
        log_error "Rollback failed"
        exit 1
    fi
}

################################################################################
# Delete a single stack
################################################################################
delete_stack() {
    local stack_name=$1
    local full_stack_name="${STACK_PREFIX}-${ENVIRONMENT}-${stack_name}"
    
    log_warning "Deleting stack: $full_stack_name"
    
    if ! aws cloudformation describe-stacks \
        --stack-name "$full_stack_name" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Stack does not exist: $full_stack_name"
        return 0
    fi
    
    log_info "Deleting..."
    if aws cloudformation delete-stack \
        --stack-name "$full_stack_name" \
        --region "$AWS_REGION"; then
        
        log_info "Waiting for deletion to complete..."
        if aws cloudformation wait stack-delete-complete \
            --stack-name "$full_stack_name" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "Stack deleted: $full_stack_name"
        else
            log_warning "Stack deletion may have failed, check AWS console"
        fi
    else
        log_error "Failed to delete stack"
        return 1
    fi
}

################################################################################
# Delete all stacks
################################################################################
delete_all_stacks() {
    log_warning "===== Delete All Stacks ====="
    echo ""
    log_warning "This will delete ALL infrastructure for $ENVIRONMENT environment"
    log_warning "Stack Prefix: $STACK_PREFIX"
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Deletion cancelled"
        exit 0
    fi
    
    echo ""
    log_info "Deleting stacks in reverse order..."
    echo ""
    
    # Delete in reverse order (opposite of creation)
    delete_stack "service"
    delete_stack "task"
    delete_stack "cluster"
    delete_stack "alb"
    delete_stack "security"
    delete_stack "codebuild"
    delete_stack "ecr"
    
    log_success "All stacks deleted"
}

################################################################################
# Main
################################################################################
case "$ACTION" in
    --service)
        rollback_service
        ;;
    --delete-all)
        delete_all_stacks
        ;;
    --delete)
        if [ -z "$COMPONENT" ]; then
            log_error "Please specify a component to delete"
            log_info "Example: $0 $ENVIRONMENT --delete alb"
            exit 1
        fi
        delete_stack "$COMPONENT"
        ;;
    *)
        log_error "Invalid action: $ACTION"
        log_info "Valid actions: --service, --delete-all, --delete <component>"
        exit 1
        ;;
esac

echo ""
log_success "Done!"
echo ""