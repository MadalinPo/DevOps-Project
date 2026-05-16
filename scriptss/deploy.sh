#!/bin/bash

################################################################################
# Blue/Green Deployment Orchestrator
#
# This script manages the lifecycle of a deployment:
# 1. Updates target slot configuration
# 2. Uploads the application bundle
# 3. Executes health probes against the new deployment
# 4. Performs a zero-downtime slot swap if health checks pass
# 5. Rejects the deployment and maintains stability if health checks fail
################################################################################

set -e

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-blue-green-deployment-rg}"
APP_SERVICE_NAME="${APP_SERVICE_NAME:-bg-deployment-app}"
HEALTH_CHECK_ENDPOINT="${HEALTH_CHECK_ENDPOINT:-https}"
HEALTH_CHECK_PATH="/health"
MAX_HEALTH_CHECKS=30
HEALTH_CHECK_INTERVAL=10
SWAP_WARMUP_TIME=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
# Get Current Slot Status
################################################################################
get_current_production_slot() {
    log_info "Determining current production slot..."
    
    # Get the current traffic percentage for the green slot
    TRAFFIC_PERCENTAGE=$(az webapp traffic-routing show \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot green \
        --query "trafficPercentage" \
        -o tsv 2>/dev/null || echo "0")
    
    if [ "$TRAFFIC_PERCENTAGE" -eq "0" ]; then
        PRODUCTION_SLOT="blue"
        STAGING_SLOT="green"
        log_info "Current production: BLUE, staging: GREEN"
    else
        PRODUCTION_SLOT="green"
        STAGING_SLOT="blue"
        log_info "Current production: GREEN, staging: BLUE"
    fi
}

################################################################################
# Get Slot Hostname
################################################################################
get_slot_hostname() {
    local slot=$1
    if [ "$slot" = "blue" ]; then
        # Production slot doesn't have a slot suffix
        echo "${APP_SERVICE_NAME}.azurewebsites.net"
    else
        echo "${APP_SERVICE_NAME}-${slot}.azurewebsites.net"
    fi
}

################################################################################
# Deploy to Staging Slot
################################################################################
deploy_to_staging() {
    log_info "Deploying application bundle to $STAGING_SLOT slot..."
    
    # Generate publishing credentials
    PUBLISH_PROFILE=$(az webapp deployment list-publishing-profiles \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot "$STAGING_SLOT" \
        --xml 2>/dev/null | head -1)
    
    if [ -z "$PUBLISH_PROFILE" ]; then
        log_error "Failed to get publishing profile"
        return 1
    fi
    
    # Application deployment is performed using the zip-push method.
    
    log_info "Zipping application bundle..."
    zip -r /tmp/app-deployment.zip . \
        -x "*.git*" "*node_modules*" "*.terraform*" "*.zip" "*.md" > /dev/null 2>&1
    
    log_info "Deploying application to the $STAGING_SLOT slot..."
    az webapp deployment source config-zip \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot "$STAGING_SLOT" \
        --src /tmp/app-deployment.zip \
        > /dev/null 2>&1
    
    log_success "Deployment to $STAGING_SLOT complete"
    
    # Clean up
    rm -f /tmp/app-deployment.zip
}

################################################################################
# Health Check
################################################################################
health_check() {
    local slot=$1
    local hostname=$(get_slot_hostname "$slot")
    local url="${HEALTH_CHECK_ENDPOINT}://${hostname}${HEALTH_CHECK_PATH}"
    
    log_info "Performing health check on $slot slot..."
    log_info "Checking: $url"
    
    local checks=0
    local healthy=false
    
    while [ $checks -lt $MAX_HEALTH_CHECKS ]; do
        checks=$((checks + 1))
        
        # Perform health check
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        if [ "$RESPONSE" = "200" ]; then
            log_success "Health check passed (attempt $checks/$MAX_HEALTH_CHECKS)"
            healthy=true
            break
        else
            log_warning "Health check failed with status $RESPONSE (attempt $checks/$MAX_HEALTH_CHECKS)"
            
            if [ $checks -lt $MAX_HEALTH_CHECKS ]; then
                log_info "Waiting ${HEALTH_CHECK_INTERVAL}s before retry..."
                sleep "$HEALTH_CHECK_INTERVAL"
            fi
        fi
    done
    
    if [ "$healthy" = true ]; then
        return 0
    else
        log_error "Health check failed after $MAX_HEALTH_CHECKS attempts"
        return 1
    fi
}

################################################################################
# Swap Slots
################################################################################
swap_slots() {
    local source_slot=$1
    local target_slot=$2
    
    log_info "Warming up $source_slot slot for swap..."
    sleep "$SWAP_WARMUP_TIME"
    
    log_info "Swapping slots: $source_slot → production, $target_slot → staging..."
    
    az webapp deployment slot swap \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot "$source_slot" \
        > /dev/null 2>&1
    
    log_success "Slot swap completed successfully"
}

################################################################################
# Rollback
################################################################################
rollback() {
    log_warning "Initiating rollback..."
    log_info "Swapping back: $PRODUCTION_SLOT → production, $STAGING_SLOT → staging..."
    
    az webapp deployment slot swap \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot "$STAGING_SLOT" \
        > /dev/null 2>&1
    
    log_success "Rollback completed successfully"
}

################################################################################
# Update App Settings
################################################################################
update_app_settings() {
    local slot=$1
    local version=$2
    local simulate_failure=${3:-false}
    
    log_info "Updating app settings for $slot slot..."
    log_info "Version: $version, Simulate failure: $simulate_failure"
    
    az webapp config appsettings set \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot "$slot" \
        --settings \
        APP_VERSION="$version" \
        ENVIRONMENT="$slot" \
        SIMULATE_FAILURE="$simulate_failure" \
        > /dev/null 2>&1
    
    log_success "App settings updated"
}

################################################################################
# Main Deployment Flow
################################################################################
main() {
    local new_version="${1:-2.0.0}"
    local simulate_failure="${2:-false}"
    
    log_info "=========================================="
    log_info "Blue/Green Deployment Script"
    log_info "=========================================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "App Service: $APP_SERVICE_NAME"
    log_info "New Version: $new_version"
    log_info "Simulate Failure: $simulate_failure"
    log_info ""
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Determine current slot status
    get_current_production_slot
    
    # Update staging slot app settings
    update_app_settings "$STAGING_SLOT" "$new_version" "$simulate_failure"
    
    # Deploy to staging slot
    deploy_to_staging
    
    # Wait for deployment to stabilize
    log_info "Waiting for application to start..."
    sleep 15
    
    # Perform health checks
    if health_check "$STAGING_SLOT"; then
        log_success "Staging environment is healthy"
        
        # Perform swap
        swap_slots "$STAGING_SLOT" "$PRODUCTION_SLOT"
        
        # Verify production is healthy
        log_info "Verifying production slot health..."
        sleep 10
        
        if health_check "$PRODUCTION_SLOT"; then
            log_success "=========================================="
            log_success "Deployment successful!"
            log_success "Version $new_version is now in production"
            log_success "=========================================="
            exit 0
        else
            log_error "Production slot health check failed"
            log_warning "Performing emergency rollback..."
            rollback
            exit 1
        fi
    else
        log_error "Staging environment is unhealthy"
        log_warning "Skipping swap"
        
        if [ "$simulate_failure" = "true" ]; then
            log_info "Failure simulation was enabled - rejection is the expected outcome."
            log_info "To demonstrate manual rollback of production, execute:"
            log_info "  ./scripts/rollback.sh"
        fi
        
        exit 1
    fi
}

# Run main function
main "$@"
