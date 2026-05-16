# Blue/Green Deployment Implementation on Azure

**Course Project: DevOps & Cloud Infrastructure**

This project demonstrates a production-grade implementation of the Blue/Green deployment strategy using Microsoft Azure, Terraform, and automated Bash scripts. It showcases how to achieve zero-downtime deployments and reliable automated rollbacks.

## Abstract

In modern DevOps practices, minimizing deployment risk and downtime is critical. This project implements a Blue/Green architecture on Azure App Service. By using deployment slots, we can stage new versions in an isolated environment (Green), verify their health, and then instantly switch production traffic (Blue) to the new version. If any issues are detected during or after the transition, the system supports both automated and manual rollbacks to maintain service availability.

## Technical Architecture

The system is composed of several key components:

1.  **Application Layer**: A Node.js application that serves a version-aware API and includes a dedicated `/health` endpoint for monitoring.
2.  **Infrastructure Layer**: Managed via Terraform, consisting of an Azure App Service Plan (Standard tier), a Linux Web App, and a dedicated deployment slot.
3.  **Deployment Orchestration**: Custom Bash scripts that utilize the Azure CLI to handle the deployment lifecycle: configuration, code upload, health verification, and traffic swapping.
4.  **Monitoring**: Integrated health checks and Application Insights for real-time observability.

```text
┌──────────────────────────────────────────┐
│           Azure App Service              │
├───────────────────┬──────────────────────┤
│    Blue Slot      │    Green Slot        │
│   (Production)    │    (Staging)         │
│   v1.0.0          │    v2.0.0            │
│   ✓ Healthy       │    Deploying         │
└───────────────────┴──────────────────────┘
         ↑                     ↓
         │                Health Check
         │                     ↓
     100% Traffic         [Pass / Fail]
         ↑                     │
         │                     ↓
         └─── Slot Swap ─── If Healthy
```

## Technology Stack

- **Application**: Node.js (simple, portable, no external dependencies)
- **Cloud**: Microsoft Azure App Service
- **Infrastructure as Code**: Terraform
- **Deployment**: Bash scripts with Azure CLI
- **Health Checks**: HTTP endpoints with status indicators
- **Monitoring**: Azure Application Insights (optional)

## Academic Objectives Demonstrated

* Infrastructure as Code (IaC): Using Terraform to define and provision cloud resources.
* Deployment Strategies: Practical implementation of the Blue/Green pattern.
* Automated Verification: Integrated health probes to gate deployments.
* Risk Mitigation: Demonstration of fail-safe mechanisms and rollbacks.
* Cloud Observability: Basic monitoring and health reporting.

## Project Structure

```
blue-green-deployment/
├── app.js                          # Node.js application
├── package.json                    # Dependencies
│
├── terraform/
│   └── main.tf                    # Infrastructure definition
│
├── scripts/
│   ├── setup.sh                   # Initial setup & infrastructure
│   ├── deploy.sh                  # Deploy new version
│   ├── rollback.sh                # Manual rollback
│   └── monitor.sh                 # Health monitoring
│
└── README.md                      # This file
```

## Prerequisites

### Required Tools
- **Azure CLI** (v2.30+): `https://docs.microsoft.com/cli/azure/`
- **Terraform** (v1.0+): `https://www.terraform.io/downloads`
- **Bash**: Available on Linux, macOS, and Windows (WSL/Git Bash)
- **curl**: For health checks (usually pre-installed)


## Setup Instructions

### 1. Prepare the Environment

```bash
# Make setup script executable
chmod +x scripts/setup.sh

# Set Azure subscription (optional, in case of multiple subscriptions)
export SUBSCRIPTION_ID="<azure-subscription-id>"
az account set --subscription "$SUBSCRIPTION_ID"
```

### 2. Configure Deployment Parameters

Edit environment variables (optional):
```bash
# Custom resource group name
export RESOURCE_GROUP="my-blue-green-rg"

# Azure region (select based on geographic proximity)
export LOCATION="eastus"  # Selection based on geographic proximity

# App service name (must be globally unique)
export APP_SERVICE_NAME="my-blue-green-app-$RANDOM"
```

### 3. Run Setup Script

```bash
# This will:
# - Check prerequisites
# - Authenticate with Azure
# - Initialize Terraform
# - Deploy infrastructure to Azure
./scripts/setup.sh
```

The setup process will:
1. Verify all tools are installed
2. Authenticate to Azure
3. Show Terraform plan for approval
4. Deploy App Service with blue/green slots
5. Configure health checks
6. Output endpoint URLs

### 4. Verify Deployment

```bash
# Get the app URL from Terraform output
terraform output -json | jq '.app_service_default_hostname.value'

# Test the application
curl https://bg-deployment-app.azurewebsites.net/
curl https://bg-deployment-app.azurewebsites.net/api/status | jq .
```

## Usage Guide

### Standard Deployment

Deploy a new version without simulating failure:

```bash
./scripts/deploy.sh 2.0.0
```

The script will:
1. Deploy to staging slot (green)
2. Perform health checks
3. If healthy, swap slots (blue ↔ green)
4. Verify production is healthy
5. Result: Zero-downtime production deployment

**Expected output**:
```
[INFO] Deploying application to green slot...
[INFO] Performing health check on green slot...
[SUCCESS] Health check passed (attempt 1/30)
[INFO] Swapping slots: green → production...
[SUCCESS] Deployment successful!
```

### Test Failure & Rollback

Deploy with failure simulation to test automated rollback:

```bash
./scripts/deploy.sh 2.0.0 true
```

The script will:
1. Deploy to staging with failure simulation enabled
2. Attempt health checks
3. Health checks fail (application returns 503 errors)
4. Deployment is rejected
5. **No swap occurs** — production remains healthy
6. Result: Failed deployment safely contained

**Expected output**:
```
[INFO] Deploying application to green slot...
[INFO] Updating app settings for green slot...
[INFO] Performing health check on green slot...
[WARNING] Health check failed with status 503 (attempt 1/30)
...
[ERROR] Health check failed after 30 attempts
[ERROR] Staging environment is unhealthy
[WARNING] Skipping swap
```

### Manual Rollback (Emergency)

If production deployment fails health checks after swap:

```bash
./scripts/rollback.sh
```

The script will:
1. Identify current production slot
2. Verify staging slot is healthy
3. Perform slot swap to restore previous version
4. Verify health of restored version
5. Result: Production restored to known-good version

**Use case**: Production issues discovered post-deployment that weren't caught by health checks

### Monitor Slot Health

Continuously monitor both slots:

```bash
./scripts/monitor.sh
```

Displays every 60 seconds:
- Health status of both slots
- Response times
- Traffic distribution
- Version information
- Logs to `/tmp/blue-green-health.log`

## Demonstration Scenario

### Complete End-to-End Demo

1. **Initial deployment** (v1.0.0):
   ```bash
   # App is running on blue slot (production)
   curl https://bg-deployment-app.azurewebsites.net/api/version
   # Output: {"version":"1.0.0","environment":"blue"}
   ```

2. **Successful deployment** (v2.0.0):
   ```bash
   ./scripts/deploy.sh 2.0.0
   
   # App is now running on green slot (was blue before)
   curl https://bg-deployment-app.azurewebsites.net/api/version
   # Output: {"version":"2.0.0","environment":"green"}
   ```

3. **Simulate failure** (v3.0.0 bad release):
   ```bash
   ./scripts/deploy.sh 3.0.0 true
   
   # Health checks fail
   # Deployment is rejected (no swap)
   # v2.0.0 remains in production
   
   curl https://bg-deployment-app.azurewebsites.net/api/version
   # Output: {"version":"2.0.0","environment":"green"} (unchanged)
   ```

4. **Check staging for debugging**:
   ```bash
   # Access failing deployment on green slot
   curl https://bg-deployment-app-green.azurewebsites.net/api/version
   # Output: {"version":"3.0.0","environment":"blue"}
   
   # Health endpoint returns 503
   curl https://bg-deployment-app-green.azurewebsites.net/health
   # Output: {"status":"unhealthy","version":"3.0.0",...}
   ```

5. **Manual rollback** (if needed):
   ```bash
   ./scripts/rollback.sh
   
   # Confirms staging (blue) is healthy
   # Swaps to restore previous version
   ```

## Configuration Reference

### App Settings

Customize behavior via environment variables:

```bash
# Application version (used for tracking)
APP_VERSION="2.0.0"

# Current slot identifier (blue or green)
ENVIRONMENT="blue"

# Simulate health check failure
SIMULATE_FAILURE="false"  # Set to "true" to trigger failure

# Node.js HTTP port
PORT="8080"
```

### Health Check Configuration

Edit in `terraform/main.tf`:

```hcl
# Health check path
health_check_path = "/health"

# Expected response time
# Auto-heal if exceeds threshold
auto_heal_enabled = true
```

### Deployment Behavior

Edit in `scripts/deploy.sh`:

```bash
# Maximum health check attempts
MAX_HEALTH_CHECKS=30

# Delay between health check retries (seconds)
HEALTH_CHECK_INTERVAL=10

# Warm-up time before slot swap (seconds)
SWAP_WARMUP_TIME=30
```

## API Endpoints

### Production Application

**Health Check Endpoint**:
```
GET /health

Response (Healthy):
{
  "status": "healthy",
  "version": "2.0.0",
  "environment": "green",
  "uptime": 1234.5
}

Response (Unhealthy):
{
  "status": "unhealthy",
  "version": "3.0.0",
  "environment": "blue",
  "message": "Simulated failure: Service unavailable"
}
```

**Status Endpoint**:
```
GET /api/status

Response:
{
  "environment": "green",
  "version": "2.0.0",
  "hostname": "bg-deployment-app.azurewebsites.net",
  "uptime": 5432.1,
  "timestamp": "2026-03-15T10:30:45.123Z",
  "node_version": "v18.12.0"
}
```

**Version Endpoint**:
```
GET /api/version

Response:
{
  "version": "2.0.0",
  "environment": "green"
}
```

## Troubleshooting

### Health Checks Timing Out

**Problem**: Deployment takes 60+ seconds to stabilize

**Solutions**:
- Increase `MAX_HEALTH_CHECKS` in deploy.sh
- Increase `HEALTH_CHECK_INTERVAL` to allow more time
- Check Azure activity logs for errors: `az webapp log show`

### Slot Swap Fails

**Problem**: "Cannot swap slots" error

**Causes**:
- App Service Plan must be S1 or higher (Free/Basic tiers don't support slots)
- Deployment may have partially failed

**Solution**:
```bash
# Upgrade App Service Plan
az appservice plan update --sku S1 --name "$APP_SERVICE_PLAN_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Retry deployment
./scripts/deploy.sh 2.0.0
```

### Can't Connect to Application

**Problem**: "Connection refused" or timeout

**Checks**:
```bash
# Verify App Service is running
az webapp show --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" --query state

# Check recent logs
az webapp log tail --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Verify health endpoint
curl -i https://bg-deployment-app.azurewebsites.net/health
```

### Azure CLI Authentication

**Problem**: "Not authenticated" error

**Solution**:
```bash
# Re-authenticate
az login

# For service principal:
az login --service-principal -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID
```

## Cleanup

To remove all Azure resources and avoid charges:

```bash
cd terraform
terraform destroy -var="resource_group_name=$RESOURCE_GROUP" \
                 -var="app_service_name=$APP_SERVICE_NAME"

# Or manually delete resource group
az group delete --name "$RESOURCE_GROUP" --yes
```

## Advanced Topics

### Custom Application

Replace the default `app.js` with a custom implementation:

1. Ensure the application listens on the `$PORT` environment variable
2. Implement `/health` endpoint returning:
   - HTTP 200 if healthy
   - HTTP 5xx if unhealthy (for failure testing)
3. Redeploy:
   ```bash
   ./scripts/deploy.sh <version>
   ```

### CI/CD Integration

Deploy from GitHub Actions, Azure DevOps, or Jenkins:

```bash
# CI/CD pipeline implementation example:
export RESOURCE_GROUP="prod-rg"
export APP_SERVICE_NAME="prod-app"

./scripts/deploy.sh "$GITHUB_SHA" false
```

### Infrastructure as Code

Modify `terraform/main.tf` to:
- Change App Service Plan tier
- Add custom domains
- Configure SSL certificates
- Add Application Insights
- Set environment variables

After changes:
```bash
cd terraform
terraform plan -out=tfplan
terraform apply tfplan
```

### Monitoring & Alerts

Set up alerts in Azure Portal:
1. Application Insights → Alerts
2. Create alert rule for failed health checks
3. Trigger runbook for automatic rollback
4. Integration with PagerDuty/Slack

## Project Requirements Checklist

- Configure blue/green deployment — Azure App Service slots
- Simulate bad release — Failure simulation flag in app settings
- Demonstrate automated rollback — Health checks + slot swap
- Zero-downtime deployment — Slot swap mechanism
- Documentation — Complete setup and usage guide
- GitHub repository — This project
