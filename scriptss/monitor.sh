#!/bin/bash

################################################################################
# Health Monitoring Script
# 
# Continuously monitors both deployment slots and logs their status
################################################################################

set -e

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-blue-green-deployment-rg}"
APP_SERVICE_NAME="${APP_SERVICE_NAME:-bg-deployment-app}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
LOG_FILE="/tmp/blue-green-health.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
    echo -e "${GREEN}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    echo -e "${YELLOW}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

################################################################################
# Check Slot Health
################################################################################
check_slot_health() {
    local slot=$1
    local hostname
    
    if [ "$slot" = "blue" ]; then
        hostname="${APP_SERVICE_NAME}.azurewebsites.net"
    else
        hostname="${APP_SERVICE_NAME}-${slot}.azurewebsites.net"
    fi
    
    local url="https://${hostname}/health"
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    local response_time=$(curl -s -w "%{time_total}" -o /dev/null "$url" 2>/dev/null || echo "0")
    
    if [ "$response_code" = "200" ]; then
        log_success "$slot slot: HEALTHY (HTTP $response_code, ${response_time}s)"
        return 0
    else
        log_error "$slot slot: UNHEALTHY (HTTP $response_code)"
        return 1
    fi
}

################################################################################
# Get Detailed Status
################################################################################
get_detailed_status() {
    local slot=$1
    local hostname
    
    if [ "$slot" = "blue" ]; then
        hostname="${APP_SERVICE_NAME}.azurewebsites.net"
    else
        hostname="${APP_SERVICE_NAME}-${slot}.azurewebsites.net"
    fi
    
    local status_url="https://${hostname}/api/status"
    local status=$(curl -s "$status_url" 2>/dev/null || echo "{}")
    
    log_info "$slot slot details:"
    echo "$status" | jq '.' | sed 's/^/  /'
}

################################################################################
# Get Traffic Distribution
################################################################################
get_traffic_distribution() {
    log_info "Traffic distribution:"
    
    # Blue is always 100% in production (green is 0%) or vice versa
    # This shows which slot is currently in production
    local green_traffic=$(az webapp traffic-routing show \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --slot green \
        --query "trafficPercentage" \
        -o tsv 2>/dev/null || echo "0")
    
    local blue_traffic=$((100 - green_traffic))
    
    log_info "  Blue:  ${blue_traffic}%"
    log_info "  Green: ${green_traffic}%"
}

################################################################################
# Main Monitoring Loop
################################################################################
main() {
    log_info "=========================================="
    log_info "Health Monitoring Script"
    log_info "=========================================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "App Service: $APP_SERVICE_NAME"
    log_info "Check Interval: ${CHECK_INTERVAL}s"
    log_info "Log File: $LOG_FILE"
    log_info ""
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed - detailed status will be skipped"
    fi
    
    # Initialize log file
    echo "=== Blue/Green Health Monitoring Started at $(date) ===" > "$LOG_FILE"
    
    # Continuous monitoring loop
    while true; do
        log_info "=========================================="
        
        # Check both slots
        blue_healthy=false
        green_healthy=false
        
        check_slot_health "blue" && blue_healthy=true || true
        check_slot_health "green" && green_healthy=true || true
        
        # Show traffic distribution
        get_traffic_distribution
        
        # Show detailed status if both are healthy
        if [ "$blue_healthy" = true ] && [ "$green_healthy" = true ]; then
            log_info "Both slots are healthy - showing detailed status:"
            if command -v jq &> /dev/null; then
                get_detailed_status "blue"
                get_detailed_status "green"
            fi
        fi
        
        # Alert if either slot is unhealthy
        if [ "$blue_healthy" = false ] || [ "$green_healthy" = false ]; then
            log_error "One or more slots are unhealthy!"
            log_error "Consider running rollback.sh if production is affected"
        fi
        
        log_info "Next check in ${CHECK_INTERVAL}s (Ctrl+C to stop)"
        sleep "$CHECK_INTERVAL"
    done
}

# Cleanup on interrupt
trap 'log_info "Monitoring stopped"; exit 0' SIGINT SIGTERM

main "$@"
