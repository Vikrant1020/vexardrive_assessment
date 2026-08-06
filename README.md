# Fleet Ping Service

> VexarDrive Technologies — Fleet vehicle location ping ingestion and driver authentication service.

## Overview

The Fleet Ping Service is a production-ready Node.js/Express backend that receives vehicle location updates from fleet devices and handles driver authentication. It uses PostgreSQL for persistent storage and is deployed on Azure Container Apps behind an Application Gateway with WAF protection.

## Architecture

See [Architecture Diagram](docs/ARCHITECTURE.md) for the full Azure architecture with Mermaid diagram.

**Key components:**
- **Application Gateway v2 + WAF** — Edge security (OWASP 3.2, Bot Manager)
- **Azure Container Apps** (internal) — Auto-scaling serverless compute
- **PostgreSQL Flexible Server** — VNet-integrated with PgBouncer
- **Azure Key Vault** — Secrets management via Managed Identity
- **Azure Container Registry** — Private Docker image storage

## API Endpoints

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/` | No | Service info |
| `GET` | `/health` | No | Liveness probe |
| `GET` | `/ready` | No | Readiness probe (checks DB) |
| `POST` | `/api/fleet/ping` | No | Ingest vehicle location ping |
| `POST` | `/api/auth/login` | No | Driver login (returns JWT) |
| `GET` | `/api/admin/drivers` | JWT | List all drivers (admin) |

## Quick Start (Local Development)

### Prerequisites
- Node.js >= 20
- Docker & Docker Compose

### Using Docker Compose

1. Copy the environment template:
   ```bash
   cp .env.example .env
   ```

2. Fill in the secrets in `.env`:
   ```env
   POSTGRES_PASSWORD=your-secure-password
   JWT_SECRET=your-jwt-secret-key
   ```

3. Start the services:
   ```bash
   docker compose up --build
   ```

4. The service is available at `http://localhost:3000`.

### Without Docker

1. Install dependencies:
   ```bash
   npm ci
   ```

2. Set environment variables (see `.env.example` for the full list).

3. Apply the database schema:
   ```bash
   psql -h localhost -U vexaradmin -d vexar_fleet -f schema.sql
   ```

4. Start the application:
   ```bash
   npm start
   ```

## Project Structure

```
.
├── .github/
│   ├── workflows/
│   │   └── ci-cd.yml          # CI/CD pipeline
│   └── dependabot.yml         # Automated dependency updates
├── azure-infrastructure/
│   ├── env/
│   │   └── dev/
│   │       ├── main.tf            # Environment orchestration
│   │       ├── variables.tf       # Dev defaults
│   │       ├── provider.tf        # Azure provider config
│   │       └── output.tf          # Output values
│   └── modules/                   # Reusable Terraform modules (24 modules)
├── docs/
│   ├── ARCHITECTURE.md        # Architecture diagram
│   └── TECHNICAL_REPORT.md    # Full technical report
├── server.js                  # Application entry point
├── schema.sql                 # Database schema
├── package.json
├── Dockerfile                 # Multi-stage production build
├── docker-compose.yml         # Local development
├── .env.example               # Environment variable template
├── .dockerignore
└── .gitignore
```

## Documentation

- [Technical Report](docs/TECHNICAL_REPORT.md) — Full assessment report with decisions, trade-offs, and rationale
- [Architecture Diagram](docs/ARCHITECTURE.md) — Azure architecture with Mermaid diagram

## Infrastructure Deployment (Terraform)

```bash
cd azure-infrastructure/env/dev

# Initialize
terraform init

# Plan (pass secrets via CLI — never commit them)
terraform plan \
  -var="tenant_id=<azure-tenant-id>" \
  -var="deployer_object_id=<your-object-id>" \
  -var="db_admin_password=<secure-password>" \
  -var="jwt_secret=<secure-jwt-secret>"

# Apply
terraform apply \
  -var="tenant_id=<azure-tenant-id>" \
  -var="deployer_object_id=<your-object-id>" \
  -var="db_admin_password=<secure-password>" \
  -var="jwt_secret=<secure-jwt-secret>"
```

CI/CD deploys to the **dev** environment (`rg-vexar-fleet-dev`, `ca-vexar-fleet-dev`, `acrvexarfleetdev`).

## Assessment Context

This repository is the submission for the **VexarDrive Technologies DevOps & Cloud Infrastructure Engineer Technical Assessment**. See [TECHNICAL_REPORT.md](docs/TECHNICAL_REPORT.md) for the full write-up.