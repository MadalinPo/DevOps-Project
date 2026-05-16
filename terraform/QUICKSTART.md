# Evaluation Guide: Quick Start

This guide provides the necessary steps for an evaluator to set up and test the Blue/Green deployment project.

## 5-Minute Setup

### Step 1: Tool Verification
Ensure the following are installed:
- Azure CLI
- Terraform (v1.0+)
- Node.js (v18+)

### Step 2: Authentication
```bash
az login
```

### Step 3: Automated Infrastructure Provisioning
```bash
./scripts/setup.sh
```
*Note: This script will prompt for confirmation after showing the Terraform plan.*

## Deployment Scenarios for Evaluation

### Scenario 1: Successful Blue/Green Deployment
Demonstrate a smooth transition from v1.0.0 to v2.0.0.
```bash
./scripts/deploy.sh 2.0.0

# Verify production is now running v2.0.0
curl https://bg-deployment-app.azurewebsites.net/api/version
```

### Scenario 2: Automated Deployment Rejection (Failure Simulation)
Demonstrate how the system handles a "bad" release by simulating a service failure.
```bash
# Deploy v3.0.0 with failure simulation enabled
./scripts/deploy.sh 3.0.0 true

# Verify production remains stable on v2.0.0 (the swap was rejected)
curl https://bg-deployment-app.azurewebsites.net/api/version
```

## Clean-up (Post-Evaluation)
```bash
cd terraform
terraform destroy -auto-approve
```
