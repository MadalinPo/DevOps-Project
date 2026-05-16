#!/bin/bash

################################################################################
# Rollback Script
# 
# Manually triggers a rollback to the previous (healthy) slot
################################################################################

set -e

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-blue-green-deployment-rg}"
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
    
    TRAFFIC_PERCENTAGE=$(az webapp traffic-routing show \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot green \
        --query "trafficPercentage" \
        -o tsv 2>/dev/null || echo "0")
    
    if [ "$TRAFFIC_PERCENTAGE" -eq "0" ]; then
        PRODUCTION_SLOT="blue"
        STAGING_SLOT="green"
    else
        PRODUCTION_SLOT="green"
        STAGING_SLOT="blue"
    fi
    
    log_info "Current production slot: $PRODUCTION_SLOT"
    log_info "Current staging slot: $STAGING_SLOT"
}

################################################################################
# Get Slot Status
################################################################################
get_slot_status() {
    local slot=$1
    local hostname
    
    if [ "$slot" = "blue" ]; then
        hostname="${APP_SERVICE_NAME}.azurewebsites.net"
    else
        hostname="${APP_SERVICE_NAME}-${slot}.azurewebsites.net"
    fi
    
    log_info "Checking health of $slot slot ($hostname)..."
    
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "https://${hostname}/health" 2>/dev/null || echo "000")
    
    if [ "$RESPONSE" = "200" ]; then
        log_success "$slot slot is healthy (HTTP $RESPONSE)"
        return 0
    else
        log_warning "$slot slot is unhealthy (HTTP $RESPONSE)"
        return 1
    fi
}

################################################################################
# Perform Rollback
################################################################################
perform_rollback() {
    log_warning "=========================================="
    log_warning "INITIATING ROLLBACK"
    log_warning "=========================================="
    log_warning "Production will be restored to: $STAGING_SLOT"
    log_warning "Failed deployment will be moved to: $PRODUCTION_SLOT"
    
    read -p "Confirm rollback operation? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi
    
    log_info "Performing slot swap..."
    az webapp deployment slot swap \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot "$STAGING_SLOT" \
        > /dev/null 2>&1
    
    log_success "Slot swap completed"
    
    # Verify
    log_info "Verifying rollback..."
    sleep 10
    
    if get_slot_status "$PRODUCTION_SLOT"; then
        log_success "=========================================="
        log_success "Rollback completed successfully!"
        log_success "Production is now on $PRODUCTION_SLOT slot"
        log_success "=========================================="
        return 0
    else
        log_error "Production slot is still unhealthy after rollback"
        log_error "Manual intervention may be required"
        return 1
    fi
}

################################################################################
# Main
################################################################################
main() {
    log_info "=========================================="
    log_info "Rollback Script"
    log_info "=========================================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "App Service: $APP_SERVICE_NAME"
    log_info ""
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Determine current slots
    get_current_production_slot
    
    # Check current production health
    if get_slot_status "$PRODUCTION_SLOT"; then
        log_info "Production slot is currently healthy"
        read -p "Proceed with rollback despite health check failure? (yes/no): " -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi
    
    # Check staging slot health
    log_info ""
    if get_slot_status "$STAGING_SLOT"; then
        log_success "Staging slot is healthy - safe to rollback"
        perform_rollback
    else
        log_error "Staging slot is unhealthy - cannot safely rollback"
        log_error "Manual intervention required"
        exit 1
    fi
}

main "$@"
