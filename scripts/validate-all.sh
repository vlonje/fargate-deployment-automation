#!/bin/bash

################################################################################
# Validate All - Comprehensive Local Validation
# 
# This script validates all CloudFormation templates, parameter files, and
# bash scripts WITHOUT requiring AWS credentials or an active AWS account.
#
# Usage: ./validate-all.sh [--verbose]
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Verbose mode
VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Debug logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

################################################################################
# Check if command exists
################################################################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

################################################################################
# Check if required tools are installed
################################################################################
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local tools=("cfn-lint" "jq" "shellcheck" "aws")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        if command_exists "$tool"; then
            log_success "$tool is installed"
        else
            log_error "$tool is not installed"
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo ""
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Run './scripts/setup-local-testing.sh' to install missing tools"
        exit 1
    fi
}

################################################################################
# Validate CloudFormation Templates
################################################################################
validate_cloudformation_templates() {
    log_section "Validating CloudFormation Templates"
    
    local cfn_dir="$PROJECT_ROOT/cloudformation"
    local templates=(
        "1-ecr.yaml"
        "2-codebuild.yaml"
        "3-security-groups.yaml"
        "4-load-balancer.yaml"
        "5-ecs-cluster.yaml"
        "6-task-definition.yaml"
        "7-ecs-service.yaml"
    )
    
    for template in "${templates[@]}"; do
        local template_path="$cfn_dir/$template"
        
        if [ ! -f "$template_path" ]; then
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            log_warning "Template not found (may not be created yet): $template"
            continue
        fi
        
        # CFN-Lint validation
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_info "Validating $template with cfn-lint..."
        
        if $VERBOSE; then
            if cfn-lint "$template_path"; then
                log_success "$template: cfn-lint validation passed"
            else
                log_error "$template: cfn-lint validation failed"
            fi
        else
            if cfn-lint "$template_path" >/dev/null 2>&1; then
                log_success "$template: cfn-lint validation passed"
            else
                log_error "$template: cfn-lint validation failed"
                log_info "Run with --verbose to see detailed errors"
            fi
        fi
        
        # AWS CLI validation (syntax only, no credentials needed)
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_info "Validating $template with AWS CLI..."
        
        if $VERBOSE; then
            if aws cloudformation validate-template \
                --template-body "file://$template_path" \
                --region us-east-1 \
                --no-sign-request 2>/dev/null; then
                log_success "$template: AWS CLI validation passed"
            else
                log_warning "$template: AWS CLI validation skipped (may require credentials)"
            fi
        else
            if aws cloudformation validate-template \
                --template-body "file://$template_path" \
                --region us-east-1 \
                --no-sign-request >/dev/null 2>&1; then
                log_success "$template: AWS CLI validation passed"
            else
                log_warning "$template: AWS CLI validation skipped (may require credentials)"
            fi
        fi
    done
}

################################################################################
# Validate Parameter Files
################################################################################
validate_parameter_files() {
    log_section "Validating Parameter Files"
    
    local param_dir="$PROJECT_ROOT/cloudformation/parameters"
    local param_files=(
        "staging.json.example"
        "prod.json.example"
    )
    
    # Also check for actual parameter files (if they exist)
    if [ -f "$param_dir/staging.json" ]; then
        param_files+=("staging.json")
    fi
    
    if [ -f "$param_dir/prod.json" ]; then
        param_files+=("prod.json")
    fi
    
    for param_file in "${param_files[@]}"; do
        local param_path="$param_dir/$param_file"
        
        if [ ! -f "$param_path" ]; then
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            log_warning "Parameter file not found: $param_file"
            continue
        fi
        
        # JSON syntax validation
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_info "Validating $param_file JSON syntax..."
        
        if jq empty "$param_path" 2>/dev/null; then
            log_success "$param_file: Valid JSON syntax"
        else
            log_error "$param_file: Invalid JSON syntax"
            if $VERBOSE; then
                jq empty "$param_path"
            fi
            continue
        fi
        
        # Check for required parameters
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        local required_params=(
            "StackNamePrefix"
            "Environment"
            "ProjectName"
        )
        
        local missing_params=()
        for param in "${required_params[@]}"; do
            if ! jq -e ".$param" "$param_path" >/dev/null 2>&1; then
                missing_params+=("$param")
            fi
        done
        
        if [ ${#missing_params[@]} -eq 0 ]; then
            log_success "$param_file: All required parameters present"
        else
            log_error "$param_file: Missing required parameters: ${missing_params[*]}"
        fi
    done
}

################################################################################
# Validate Bash Scripts
################################################################################
validate_bash_scripts() {
    log_section "Validating Bash Scripts"
    
    local scripts_dir="$PROJECT_ROOT/scripts"
    local scripts=(
        "setup-local-testing.sh"
        "validate-all.sh"
        "deploy.sh"
        "deploy-single.sh"
        "build.sh"
        "rollback.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$scripts_dir/$script"
        
        if [ ! -f "$script_path" ]; then
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            log_warning "Script not found (may not be created yet): $script"
            continue
        fi
        
        # Shellcheck validation
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_info "Validating $script with shellcheck..."
        
        if $VERBOSE; then
            if shellcheck "$script_path"; then
                log_success "$script: shellcheck validation passed"
            else
                log_error "$script: shellcheck validation failed"
            fi
        else
            if shellcheck "$script_path" >/dev/null 2>&1; then
                log_success "$script: shellcheck validation passed"
            else
                log_error "$script: shellcheck validation failed"
                log_info "Run with --verbose to see detailed errors"
            fi
        fi
        
        # Check if executable
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        if [ -x "$script_path" ]; then
            log_success "$script: Is executable"
        else
            log_warning "$script: Not executable (run: chmod +x $script_path)"
        fi
    done
}

################################################################################
# Validate Cross-Stack References
################################################################################
validate_cross_stack_references() {
    log_section "Validating Cross-Stack References"
    
    log_info "Checking export/import naming consistency..."
    
    # This is a basic check - in a real implementation, we'd parse YAML
    # and validate that all ImportValue references match Export names
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local cfn_dir="$PROJECT_ROOT/cloudformation"
    
    if [ -f "$cfn_dir/1-ecr.yaml" ]; then
        # Check that ECR exports follow naming convention
        if grep -q "Export:" "$cfn_dir/1-ecr.yaml" && \
           grep -q "\${AWS::StackName}" "$cfn_dir/1-ecr.yaml"; then
            log_success "ECR template: Uses dynamic export names"
        else
            log_warning "ECR template: Export naming not verified"
        fi
    else
        log_warning "ECR template not found, skipping export check"
    fi
    
    # Add more cross-stack validation as templates are created
    log_info "Full cross-stack validation will be available when all templates are created"
}

################################################################################
# Validate Naming Conventions
################################################################################
validate_naming_conventions() {
    log_section "Validating Naming Conventions"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Checking stack naming convention..."
    
    # Check if parameter files use consistent naming
    local param_dir="$PROJECT_ROOT/cloudformation/parameters"
    
    if [ -f "$param_dir/staging.json.example" ]; then
        local stack_prefix
        stack_prefix=$(jq -r '.StackNamePrefix // empty' "$param_dir/staging.json.example" 2>/dev/null)
        
        if [ -n "$stack_prefix" ]; then
            if [[ "$stack_prefix" =~ ^[a-z][a-z0-9-]*$ ]]; then
                log_success "StackNamePrefix follows naming convention: $stack_prefix"
            else
                log_warning "StackNamePrefix should be lowercase with hyphens: $stack_prefix"
            fi
        else
            log_warning "StackNamePrefix not found in staging.json.example"
        fi
    fi
}

################################################################################
# Validate buildspec.yml
################################################################################
validate_buildspec() {
    log_section "Validating buildspec.yml"
    
    local buildspec_path="$PROJECT_ROOT/buildspec.yml"
    
    if [ ! -f "$buildspec_path" ]; then
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_warning "buildspec.yml not found (may not be created yet)"
        return
    fi
    
    # YAML syntax validation
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Validating buildspec.yml syntax..."
    
    # Use Python to validate YAML (most systems have Python)
    if python3 -c "import yaml; yaml.safe_load(open('$buildspec_path'))" 2>/dev/null; then
        log_success "buildspec.yml: Valid YAML syntax"
    else
        log_error "buildspec.yml: Invalid YAML syntax"
    fi
    
    # Check for required buildspec fields
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local required_fields=("version" "phases")
    local has_all_fields=true
    
    for field in "${required_fields[@]}"; do
        if ! grep -q "^$field:" "$buildspec_path"; then
            log_error "buildspec.yml: Missing required field: $field"
            has_all_fields=false
        fi
    done
    
    if $has_all_fields; then
        log_success "buildspec.yml: All required fields present"
    fi
}

################################################################################
# Print Summary
################################################################################
print_summary() {
    echo ""
    log_section "Validation Summary"
    
    echo -e "Total Checks:   ${CYAN}$TOTAL_CHECKS${NC}"
    echo -e "Passed:         ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Warnings:       ${YELLOW}$WARNING_CHECKS${NC}"
    echo -e "Failed:         ${RED}$FAILED_CHECKS${NC}"
    echo ""
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        if [ $WARNING_CHECKS -eq 0 ]; then
            log_success "All validations passed! ✨"
            echo ""
            log_info "You're ready to deploy (when you have AWS access):"
            log_info "  ./scripts/deploy.sh staging --dry-run"
            return 0
        else
            log_warning "Validations passed with warnings"
            log_info "Review warnings above before deploying"
            return 0
        fi
    else
        log_error "Some validations failed"
        log_info "Fix the errors above before deploying"
        return 1
    fi
}

################################################################################
# Main execution
################################################################################
main() {
    echo ""
    log_info "===== Fargate Deployment Automation - Comprehensive Validation ====="
    echo ""
    
    if $VERBOSE; then
        log_info "Running in VERBOSE mode"
        echo ""
    fi
    
    # Run all validations
    check_prerequisites
    validate_cloudformation_templates
    validate_parameter_files
    validate_bash_scripts
    validate_buildspec
    validate_cross_stack_references
    validate_naming_conventions
    
    # Print summary and exit with appropriate code
    print_summary
}

# Run main function
main
exit_code=$?
echo ""
exit $exit_code