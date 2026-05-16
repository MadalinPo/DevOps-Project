#!/bin/bash

################################################################################
# Infrastructure Provisioning Script
# 
# This script initializes the cloud environment:
# 1. Verifies local environment requirements
# 2. Authenticates the session with Azure
# 3. Provisions infrastructure via Terraform
# 4. Configures deployment scripts for the local environment
################################################################################

set -e

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-blue-green-deployment-rg}"
LOCATION="${LOCATION:-eastus}"
APP_SERVICE_NAME="${APP_SERVICE_NAME:-bg-deployment-app}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
# Check Prerequisites
################################################################################
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=false
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Visit: https://docs.microsoft.com/cli/azure/"
        missing=true
    fi
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Visit: https://www.terraform.io/"
        missing=true
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Visit: https://git-scm.com/"
        missing=true
    fi
    
    if [ "$missing" = true ]; then
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

################################################################################
# Azure Login
################################################################################
azure_login() {
    log_info "Checking Azure CLI authentication..."
    
    if ! az account show > /dev/null 2>&1; then
        log_info "Not authenticated. Running 'az login'..."
        az login
    fi
    
    local subscription=$(az account show --query id -o tsv)
    log_success "Authenticated to subscription: $subscription"
}

################################################################################
# Initialize Terraform
################################################################################
init_terraform() {
    log_info "Initializing Terraform..."
    
    cd "$(dirname "$0")/../terraform" || exit 1
    
    terraform init
    
    log_success "Terraform initialized"
    
    cd - > /dev/null
}

################################################################################
# Deploy Infrastructure
################################################################################
deploy_infrastructure() {
    log_info "Deploying Azure infrastructure resources..."
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "App Service: $APP_SERVICE_NAME"
    
    cd "$(dirname "$0")/../terraform" || exit 1
    
    terraform plan -var="resource_group_name=$RESOURCE_GROUP" \
                  -var="location=$LOCATION" \
                  -var="app_service_name=$APP_SERVICE_NAME" \
                  -out=tfplan
    
    read -p "Review the plan above. Continue with deployment? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deployment cancelled"
        rm tfplan
        exit 0
    fi
    
    terraform apply tfplan
    
    rm tfplan
    
    log_success "Infrastructure deployed successfully"
    
    # Get outputs
    log_info "Infrastructure outputs:"
    terraform output
    
    cd - > /dev/null
}

################################################################################
# Configure Scripts
################################################################################
configure_scripts() {
    log_info "Making scripts executable..."
    
    local script_dir="$(dirname "$0")"
    chmod +x "$script_dir/deploy.sh"
    chmod +x "$script_dir/rollback.sh"
    chmod +x "$script_dir/monitor.sh"
    
    log_success "Scripts configured"
}

################################################################################
# Initialize Git Repository
################################################################################
init_git_repo() {
    log_info "Initializing Git repository..."
    
    if [ ! -d .git ]; then
        git init
        git config user.email "deployment@example.com"
        git config user.name "Deployment System"
        log_success "Git repository initialized"
    else
        log_info "Git repository already exists"
    fi
}

################################################################################
# Main
################################################################################
main() {
    log_info "=========================================="
    log_info "Blue/Green Deployment Setup"
    log_info "=========================================="
    log_info ""
    
    check_prerequisites
    azure_login
    init_git_repo
    init_terraform
    deploy_infrastructure
    configure_scripts
    
    log_info ""
    log_info "=========================================="
    log_success "Setup completed successfully!"
    log_success "=========================================="
    log_info ""
    log_info "Deployment Instructions:"
    log_info "1. Review the infrastructure outputs provided above."
    log_info "2. Perform initial deployment:"
    log_info "   ./scripts/deploy.sh 1.0.0"
    log_info ""
    log_info "3. Conduct failure simulation and verify rollback functionality:"
    log_info "   ./scripts/deploy.sh 2.0.0 true"
    log_info ""
    log_info "4. Execute health monitoring:"
    log_info "   ./scripts/monitor.sh"
    log_info ""
}

main "$@"
