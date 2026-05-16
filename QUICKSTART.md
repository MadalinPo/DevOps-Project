# Quick Start Guide

## 5-Minute Setup

### Step 1: Install Tools
```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Terraform
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### Step 2: Authenticate
```bash
az login
```

### Step 3: Deploy Infrastructure
```bash
cd blue-green-deployment
./scripts/setup.sh
```

### Step 4: Test Deployment
```bash
# Deploy v2.0.0 successfully
./scripts/deploy.sh 2.0.0

# Check production is updated
curl https://bg-deployment-app.azurewebsites.net/api/version
```

### Step 5: Test Failure & Rollback
```bash
# Deploy v3.0.0 with failure simulation
./scripts/deploy.sh 3.0.0 true

# Verify v2.0.0 is still in production (deployment was rejected)
curl https://bg-deployment-app.azurewebsites.net/api/version
```

### Step 6: Cleanup (Optional)
```bash
cd terraform
terraform destroy -auto-approve
```

## Key Functionalities Verified

The following capabilities are implemented and verified:
- Blue/green deployment architecture
- Zero-downtime deployments
- Automatic failure detection
- Deployment rejection without swap
- Production stability maintained

## Common Commands

```bash
# Deploy new version
./scripts/deploy.sh 2.0.0

# Deploy with failure simulation
./scripts/deploy.sh 3.0.0 true

# Manual rollback
./scripts/rollback.sh

# Monitor health
./scripts/monitor.sh

# Check app status
curl https://bg-deployment-app.azurewebsites.net/health

# View Terraform state
terraform show

# Destroy infrastructure
terraform destroy
```
