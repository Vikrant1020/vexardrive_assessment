# Azure Infrastructure Automation

This repository contains the Terraform automation code for deploying and managing Azure infrastructure for the **Vexar Fleet** project.

## Architecture & Structure

The codebase has been designed for maximum modularity and reusability, inspired by best-practice enterprise patterns.

### Directory Layout

- `env/`: Contains environment-specific configurations (e.g., `dev`, `prod`, `qa`). These are the root modules where you execute Terraform commands.
  - `dev/`: The Development environment.
- `modules/`: Contains reusable, parameterized Terraform modules categorized by domain:
  - `backend/`: Application Gateway, Container Apps, Container Registries, WAF.
  - `database/`: PostgreSQL Flexible Server, databases, and configurations.
  - `monitoring/`: Log Analytics, Application Insights, Action Groups, and Alerts.
  - `networking/`: Virtual Networks, Subnets, NSGs, Private Endpoints, and DNS Zones.
  - `security/`: Key Vault, Secrets, and Role Assignments.

### Key Features

- **Fully Dynamic Modules**: Every module is completely parameterized (no hardcoded values). Components like Application Gateways, Network Security Groups, and Container Apps accept complex object lists to build resources dynamically.
- **Strict Security Posture**:
  - Almost all resources communicate securely via **Azure Private Endpoints**.
  - **User-Assigned Managed Identities** are heavily utilized (e.g., for pulling images from ACR and reading secrets from Key Vault).
  - WAF policies are attached to the Application Gateway.
- **Remote State**: The backend state is configured to be stored securely in an Azure Storage Account.

## Getting Started

### Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/downloads) (>= 1.5.0)
2. Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
3. Authenticate with Azure:
   ```bash
   az login
   az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
   ```

### Using `clean.sh`

A utility script `clean.sh` is provided in the root of the repository to streamline standard developer workflows. It performs three main tasks:

1. **Formats** all Terraform files recursively using `terraform fmt`.
2. **Validates** all environments sequentially using `terraform validate` (ensuring module references and syntaxes are correct across the board).
3. **Cleans up** temporary, unneeded local state and directory caches (e.g., `.terraform/`, `*.tfstate`).
   *Note: `clean.sh` has been specifically configured to **preserve** `.terraform.lock.hcl` files, as these should be committed to version control to guarantee provider version consistency across your team.*

To use it:
```bash
# Make sure the script is executable
chmod +x clean.sh

# Run the script
./clean.sh
```

### Deploying an Environment

To deploy or update an environment (e.g., `dev`), follow these steps:

1. **Navigate to the environment directory**:
   ```bash
   cd env/dev
   ```

2. **Initialize Terraform**:
   Downloads providers and configures the backend.
   ```bash
   terraform init
   ```

3. **Plan the changes**:
   Review what Terraform intends to create, modify, or destroy.
   ```bash
   terraform plan -out=tfplan
   ```
   *(You may need to provide variable inputs or a `.tfvars` file if variables do not have default values).*

4. **Apply the changes**:
   Execute the plan.
   ```bash
   terraform apply tfplan
   ```

## Maintenance & Best Practices

1. **Adding New Resources**: 
   - Check if an existing module in `modules/` can be reused.
   - If a new module is required, place it in the appropriate category folder (e.g., `modules/database/new_module`).
   - Keep modules generic and variable-driven. Avoid hardcoding environment-specific values in the `modules/` directory.

2. **Provider Versioning**: 
   - The AzureRM provider is currently pinned to `~> 5.0`. 
   - Always commit the `.terraform.lock.hcl` file. If you need to upgrade providers, run `terraform init -upgrade` and commit the modified lock file.

3. **Validation**: 
   - Never merge changes without running `./clean.sh` first to ensure code is formatted and strictly valid.
