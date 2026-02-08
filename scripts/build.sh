#!/bin/bash

################################################################################
# Trigger CodeBuild
#
# This script manually triggers a CodeBuild to build and deploy your Docker image.
#
# Usage: ./build.sh <environment>
#
# Examples:
#   ./build.sh staging
#   ./build.sh prod
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
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
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <environment>"
    log_info "Example: $0 staging"
    exit 1
fi

ENVIRONMENT=$1

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

BUILD_PROJECT="${STACK_PREFIX}-${ENVIRONMENT}-build"

################################################################################
# Trigger build
################################################################################
echo ""
log_info "===== Trigger CodeBuild ====="
echo ""
log_info "Environment:    $ENVIRONMENT"
log_info "Build Project:  $BUILD_PROJECT"
log_info "Region:         $AWS_REGION"
echo ""

log_info "Starting build..."

if BUILD_ID=$(aws codebuild start-build \
    --project-name "$BUILD_PROJECT" \
    --region "$AWS_REGION" \
    --query 'build.id' \
    --output text 2>&1); then
    
    log_success "Build started successfully!"
    echo ""
    log_info "Build ID: $BUILD_ID"
    echo ""
    log_info "Monitor build progress:"
    echo "  aws codebuild batch-get-builds --ids $BUILD_ID --region $AWS_REGION"
    echo ""
    log_info "Or view in AWS Console:"
    echo "  https://console.aws.amazon.com/codesuite/codebuild/projects/$BUILD_PROJECT/history"
    echo ""
    
    # Optionally wait for build to complete
    read -p "Wait for build to complete? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Waiting for build to complete..."
        
        while true; do
            BUILD_STATUS=$(aws codebuild batch-get-builds \
                --ids "$BUILD_ID" \
                --region "$AWS_REGION" \
                --query 'builds[0].buildStatus' \
                --output text)
            
            if [[ "$BUILD_STATUS" == "IN_PROGRESS" ]]; then
                echo -n "."
                sleep 5
            elif [[ "$BUILD_STATUS" == "SUCCEEDED" ]]; then
                echo ""
                log_success "Build completed successfully!"
                
                # Show build logs URL
                log_info "Build logs:"
                LOG_URL=$(aws codebuild batch-get-builds \
                    --ids "$BUILD_ID" \
                    --region "$AWS_REGION" \
                    --query 'builds[0].logs.deepLink' \
                    --output text)
                echo "  $LOG_URL"
                
                # Check ECS service status
                echo ""
                log_info "Checking ECS service deployment..."
                
                SERVICE_NAME="${STACK_PREFIX}-${ENVIRONMENT}-service"
                CLUSTER_NAME="${STACK_PREFIX}-${ENVIRONMENT}-cluster"
                
                if aws ecs describe-services \
                    --cluster "$CLUSTER_NAME" \
                    --services "$SERVICE_NAME" \
                    --region "$AWS_REGION" \
                    --query 'services[0].deployments' \
                    --output table 2>/dev/null; then
                    log_success "ECS service is updating with new image"
                fi
                
                break
            elif [[ "$BUILD_STATUS" == "FAILED" ]] || [[ "$BUILD_STATUS" == "FAULT" ]] || [[ "$BUILD_STATUS" == "STOPPED" ]] || [[ "$BUILD_STATUS" == "TIMED_OUT" ]]; then
                echo ""
                log_error "Build failed with status: $BUILD_STATUS"
                
                # Show build logs URL
                log_info "Check build logs:"
                LOG_URL=$(aws codebuild batch-get-builds \
                    --ids "$BUILD_ID" \
                    --region "$AWS_REGION" \
                    --query 'builds[0].logs.deepLink' \
                    --output text)
                echo "  $LOG_URL"
                
                exit 1
            fi
        done
    fi
    
else
    log_error "Failed to start build"
    log_error "$BUILD_ID"
    exit 1
fi

echo ""
log_success "Done!"
echo ""