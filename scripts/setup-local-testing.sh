#!/bin/bash

################################################################################
# Setup Local Testing Environment
# 
# This script installs all necessary tools for validating CloudFormation
# templates, bash scripts, and JSON files WITHOUT requiring an AWS account.
#
# VIRTUAL ENVIRONMENT (RECOMMENDED):
# If you encounter pip installation errors on Ubuntu/Debian systems, use a
# virtual environment:
#   1. sudo apt install python3-venv python3-full -y
#   2. python3 -m venv venv
#   3. source venv/bin/activate
#   4. ./scripts/setup-local-testing.sh
#
# Usage: ./setup-local-testing.sh
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Debug logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# Check if command exists
################################################################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

################################################################################
# Detect OS
################################################################################
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists apt-get; then
            OS="ubuntu"
        elif command_exists yum; then
            OS="centos"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    log_info "Detected OS: $OS"
}

################################################################################
# Install Python and pip (if needed)
################################################################################
install_python() {
    log_info "Checking Python installation..."
    
    if command_exists python3; then
        PYTHON_VERSION=$(python3 --version)
        log_success "Python is already installed: $PYTHON_VERSION"
    else
        log_warning "Python3 not found. Installing..."
        
        case $OS in
            ubuntu)
                sudo apt-get update
                sudo apt-get install -y python3 python3-pip
                ;;
            centos)
                sudo yum install -y python3 python3-pip
                ;;
            macos)
                if command_exists brew; then
                    brew install python3
                else
                    log_error "Homebrew not found. Please install Python3 manually."
                    exit 1
                fi
                ;;
            *)
                log_error "Unsupported OS. Please install Python3 manually."
                exit 1
                ;;
        esac
        
        log_success "Python3 installed successfully"
    fi
    
    # Check pip
    if command_exists pip3; then
        log_success "pip3 is available"
    else
        log_error "pip3 not found. Please install pip3 manually."
        exit 1
    fi
}

################################################################################
# Install cfn-lint (CloudFormation Linter)
################################################################################
install_cfn_lint() {
    log_info "Checking cfn-lint installation..."
    
    if command_exists cfn-lint; then
        CFN_LINT_VERSION=$(cfn-lint --version)
        log_success "cfn-lint is already installed: $CFN_LINT_VERSION"
    else
        log_warning "cfn-lint not found. Installing..."
        
        # Try installing with --user flag first
        if pip3 install --user cfn-lint 2>/dev/null; then
            log_success "cfn-lint installed successfully with --user flag"
        else
            log_warning "Installation with --user failed. You may need to use a virtual environment."
            log_info ""
            log_info "If you encounter errors, try using a virtual environment:"
            log_info "  1. Install python3-venv: sudo apt install python3-venv python3-full -y"
            log_info "  2. Create venv: python3 -m venv venv"
            log_info "  3. Activate venv: source venv/bin/activate"
            log_info "  4. Install cfn-lint: pip install cfn-lint"
            log_info "  5. Run this script again"
            log_info ""
            return 1
        fi
    fi
}

################################################################################
# Install jq (JSON processor)
################################################################################
install_jq() {
    log_info "Checking jq installation..."
    
    if command_exists jq; then
        JQ_VERSION=$(jq --version)
        log_success "jq is already installed: $JQ_VERSION"
    else
        log_warning "jq not found. Installing..."
        
        case $OS in
            ubuntu)
                sudo apt-get update
                sudo apt-get install -y jq
                ;;
            centos)
                sudo yum install -y jq
                ;;
            macos)
                if command_exists brew; then
                    brew install jq
                else
                    log_error "Homebrew not found. Please install jq manually."
                    exit 1
                fi
                ;;
            *)
                log_error "Unsupported OS. Please install jq manually."
                exit 1
                ;;
        esac
        
        log_success "jq installed successfully"
    fi
}

################################################################################
# Install shellcheck (Bash script linter)
################################################################################
install_shellcheck() {
    log_info "Checking shellcheck installation..."
    
    if command_exists shellcheck; then
        SHELLCHECK_VERSION=$(shellcheck --version | grep version: | awk '{print $2}')
        log_success "shellcheck is already installed: $SHELLCHECK_VERSION"
    else
        log_warning "shellcheck not found. Installing..."
        
        case $OS in
            ubuntu)
                sudo apt-get update
                sudo apt-get install -y shellcheck
                ;;
            centos)
                sudo yum install -y shellcheck
                ;;
            macos)
                if command_exists brew; then
                    brew install shellcheck
                else
                    log_error "Homebrew not found. Please install shellcheck manually."
                    exit 1
                fi
                ;;
            *)
                log_error "Unsupported OS. Please install shellcheck manually."
                exit 1
                ;;
        esac
        
        log_success "shellcheck installed successfully"
    fi
}

################################################################################
# Install AWS CLI (for syntax validation only, no credentials needed)
################################################################################
install_aws_cli() {
    log_info "Checking AWS CLI installation..."
    
    if command_exists aws; then
        AWS_VERSION=$(aws --version)
        log_success "AWS CLI is already installed: $AWS_VERSION"
    else
        log_warning "AWS CLI not found. Installing..."
        
        case $OS in
            ubuntu|centos|linux)
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                unzip -q awscliv2.zip
                sudo ./aws/install
                rm -rf aws awscliv2.zip
                ;;
            macos)
                curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
                sudo installer -pkg AWSCLIV2.pkg -target /
                rm AWSCLIV2.pkg
                ;;
            *)
                log_error "Unsupported OS. Please install AWS CLI manually."
                log_info "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                exit 1
                ;;
        esac
        
        log_success "AWS CLI installed successfully"
    fi
}

################################################################################
# Verify all installations
################################################################################
verify_installations() {
    log_info "Verifying all installations..."
    echo ""
    
    MISSING_TOOLS=()
    
    # Check Python3
    if command_exists python3; then
        echo -e "${GREEN}✓${NC} Python3: $(python3 --version)"
    else
        echo -e "${RED}✗${NC} Python3: Not found"
        MISSING_TOOLS+=("python3")
    fi
    
    # Check pip3
    if command_exists pip3; then
        echo -e "${GREEN}✓${NC} pip3: $(pip3 --version | awk '{print $1, $2}')"
    else
        echo -e "${RED}✗${NC} pip3: Not found"
        MISSING_TOOLS+=("pip3")
    fi
    
    # Check cfn-lint
    if command_exists cfn-lint; then
        echo -e "${GREEN}✓${NC} cfn-lint: $(cfn-lint --version)"
    else
        echo -e "${RED}✗${NC} cfn-lint: Not found"
        MISSING_TOOLS+=("cfn-lint")
    fi
    
    # Check jq
    if command_exists jq; then
        echo -e "${GREEN}✓${NC} jq: $(jq --version)"
    else
        echo -e "${RED}✗${NC} jq: Not found"
        MISSING_TOOLS+=("jq")
    fi
    
    # Check shellcheck
    if command_exists shellcheck; then
        echo -e "${GREEN}✓${NC} shellcheck: $(shellcheck --version | grep version: | awk '{print $2}')"
    else
        echo -e "${RED}✗${NC} shellcheck: Not found"
        MISSING_TOOLS+=("shellcheck")
    fi
    
    # Check AWS CLI
    if command_exists aws; then
        echo -e "${GREEN}✓${NC} AWS CLI: $(aws --version | awk '{print $1}')"
    else
        echo -e "${RED}✗${NC} AWS CLI: Not found"
        MISSING_TOOLS+=("aws")
    fi
    
    echo ""
    
    if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
        log_success "All tools are installed and ready to use!"
        log_info "You can now run: ./scripts/validate-all.sh"
        return 0
    else
        log_error "Missing tools: ${MISSING_TOOLS[*]}"
        log_info "Please install missing tools manually or re-run this script."
        return 1
    fi
}

################################################################################
# Main execution
################################################################################
main() {
    echo ""
    log_info "===== Fargate Deployment Automation - Local Testing Setup ====="
    echo ""
    
    # Detect OS
    detect_os
    echo ""
    
    # Install all tools
    install_python
    echo ""
    
    install_cfn_lint
    echo ""
    
    install_jq
    echo ""
    
    install_shellcheck
    echo ""
    
    install_aws_cli
    echo ""
    
    # Verify everything
    verify_installations
    echo ""
    
    log_info "===== Setup Complete ====="
    echo ""
}

# Run main function
main