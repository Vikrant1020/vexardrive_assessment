# Technical Report — VexarDrive Fleet Ping Service

**Author:** Vikrant  
**Date:** August 2026  
**Assessment:** DevOps & Cloud Infrastructure Engineer — VexarDrive Technologies

---

## 1. Initial Assessment of the Repository

The starter repository contains a minimal Node.js/Express backend with PostgreSQL, Docker configuration, and basic documentation. Upon review, I identified several critical issues across security, reliability, performance, and operational readiness.

### Repository State Summary

| File | Key Observations |
|---|---|
| `server.js` | Hardcoded credentials, SQL injection, no connection pooling, no health endpoints, no auth on admin route |
| `Dockerfile` | Uses `node:latest`, runs as root, exposes SSH port, no `.dockerignore` |
| `docker-compose.yml` | Hardcoded passwords, no healthchecks, DB port exposed to all interfaces |
| `package.json` | No tests, no dev dependencies, no engine constraint |
| `schema.sql` | Functional but lacks indexes for high-volume query patterns |
| `README.md` | Basic but adequate for the starter state |

---

## 2. Issues Identified (Prioritized by Risk)

### Critical (P0) — Immediate production risk

| # | Issue | Impact |
|---|---|---|
| 1 | **Hardcoded database credentials and JWT secret** in `server.js` | Credential exposure in version control; anyone with repo access has production DB access |
| 2 | **SQL injection** in `/api/auth/login` (string concatenation) | Allows arbitrary SQL execution — data exfiltration, table drops, privilege escalation |
| 3 | **No authentication on `/api/admin/drivers`** | Any unauthenticated user can dump the full driver database |
| 4 | **New database connection per request** (`pg.Client`) | Under fleet-scale traffic, this exhausts PostgreSQL connection limits within seconds |

### High (P1) — Significant operational risk

| # | Issue | Impact |
|---|---|---|
| 5 | **Dockerfile uses `node:latest`** | Non-deterministic builds; large image (~1 GB); may break on major Node.js upgrades |
| 6 | **Container runs as root** | If the container is compromised, the attacker has root privileges |
| 7 | **SSH port 22 exposed** in Dockerfile | Unnecessary attack surface |
| 8 | **No health or readiness endpoints** | Container orchestrators cannot detect unhealthy instances |
| 9 | **No graceful shutdown** | In-flight requests are abruptly terminated during deployments |
| 10 | **Hardcoded secrets in `docker-compose.yml`** | Same credential exposure problem as `server.js` |

### Medium (P2) — Operational improvement

| # | Issue | Impact |
|---|---|---|
| 11 | **No structured logging** | Production debugging is extremely difficult with `console.error` |
| 12 | **No input validation** on API endpoints | Missing fields cause cryptic DB errors |
| 13 | **JWT expiry of 30 days** | Stolen tokens remain valid for a month |
| 14 | **No `.dockerignore`** | Entire repo (including `.git`, `node_modules`) is sent as build context |
| 15 | **No `.gitignore`** | Risk of accidentally committing `node_modules` or `.env` files |

---

## 3. Changes Made and Why

### 3.1 Application Code (`server.js`)

| Change | Rationale |
|---|---|
| Replaced `pg.Client` with `pg.Pool` | Connection pooling reuses connections across requests, preventing connection exhaustion under load |
| Moved all secrets to environment variables | Secrets must never be in source code; environment variables are the standard pattern for 12-factor apps |
| Fixed SQL injection with parameterized queries | `$1` placeholders prevent user input from being interpreted as SQL |
| Added JWT auth middleware on admin endpoint | Prevents unauthorized data access |
| Added `/health` and `/ready` endpoints | Required for Kubernetes/Container Apps liveness and readiness probes |
| Integrated Pino for structured JSON logging | Enables log aggregation, search, and alerting in production |
| Added graceful shutdown handlers | Drains in-flight requests and closes DB pool before exit, preventing data loss during deployments |
| Reduced JWT expiry from 30d to 8h | Limits the blast radius of a stolen token |
| Added input validation | Returns clear 400 errors instead of cryptic database failures |

### 3.2 Containerization (`Dockerfile`)

| Change | Rationale |
|---|---|
| `node:latest` → `node:20-alpine` | Deterministic, minimal image (~180 MB vs ~1 GB) |
| Multi-stage build | Separates dependency installation from runtime; further reduces image size |
| `npm install` → `npm ci --omit=dev` | Deterministic installs from lockfile; excludes dev dependencies |
| Added `USER node` | Runs as non-root, limiting container escape impact |
| Removed `EXPOSE 22` | SSH has no place in a production container |
| Added `dumb-init` | Proper PID 1 signal forwarding ensures graceful shutdown works correctly |
| Added `HEALTHCHECK` | Docker engine can detect unhealthy containers |

### 3.3 Docker Compose (`docker-compose.yml`)

| Change | Rationale |
|---|---|
| Removed hardcoded passwords | Uses `.env` file (not committed) via variable substitution |
| Added `depends_on` with healthcheck condition | App waits for DB to be ready before starting |
| Bound DB port to `127.0.0.1` | Prevents the database from being accessible from the network |
| Auto-applied `schema.sql` on init | Database is ready to use immediately after `docker compose up` |
| Upgraded Postgres image to `16-alpine` | Smaller image, latest stable version |

### 3.4 Infrastructure as Code (Terraform)

See [Architecture Diagram](./ARCHITECTURE.md) for the full picture.

**Key architectural decisions:**

- **Azure Container Apps over AKS:** ACA provides serverless scaling, built-in HTTPS ingress, and revision management without the operational overhead of managing a Kubernetes cluster. For a single stateless microservice, AKS would be over-engineered.

- **Private Container App + Application Gateway with WAF:** The Container App Environment is configured as internal-only (no public endpoint). All external traffic flows through Azure Application Gateway v2 with a WAF policy (OWASP 3.2 rule set + Bot Manager). This provides defense-in-depth: WAF blocks SQL injection and XSS at the edge before traffic reaches the application.

- **PostgreSQL Flexible Server with PgBouncer:** VNet-integrated with no public endpoint. Built-in PgBouncer enabled for connection pooling at the database level, complementing the application-level `pg.Pool`. Zone-redundant HA for production.

- **Key Vault with RBAC:** Secrets stored in Key Vault, accessed by the Container App via system-assigned Managed Identity with the "Key Vault Secrets User" role. No passwords or connection strings in code or environment variable files.

- **Both secrets generated by Terraform, not typed in:** The DB admin password and the JWT signing secret are both produced with `random_password` and written straight to Key Vault (`postgresql_flexible_server/main.tf`, `env/dev/main.tf`). Earlier, `jwt_secret` was a plain `-var` an operator had to generate and pass in by hand — that's a real leak vector (shell history, CI job logs). Generating it the same way as the DB password removes that vector entirely; nobody ever sees or types the value.

- **Container image lifecycle ownership:** The Container App resource sets `lifecycle { ignore_changes = [template[0].container[0].image] }`. CI/CD deploys new image tags directly via `az containerapp update` (through `azure/container-apps-deploy-action`), not through Terraform — without this, the next `terraform apply` would silently revert the running app to whatever image is recorded in state (e.g. the `nginx:latest` placeholder default), undoing every CI deploy. This was caught during a review pass and is exactly the kind of bug that only surfaces once Terraform and a CD pipeline both touch the same resource.

- **Environment separation via tfvars:** Same Terraform modules, different variables per environment. Dev scales to zero; prod runs always-on with HA.

### 3.5 CI/CD Pipeline

**Pipeline stages:** Test → Lint → Security Scan (Trivy) → Build & Push to ACR → Deploy to Container Apps → Post-deploy health verification → Automatic rollback on failure.

**Key design decisions:**

- **OIDC authentication** (federated identity, no stored secrets) for Azure login
- **Development environment gate** — GitHub `development` environment for deploy approvals (configure in repo settings)
- **Trivy SARIF upload** integrates vulnerability findings into GitHub Security tab
- **Automatic rollback** shifts traffic back to the previous revision if health checks fail
- **Dependabot** monitors npm, GitHub Actions, and Terraform provider versions weekly

**Requirements for CI/CD:**
1. **GitHub Secrets:** Must configure `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`.
2. **Azure AD Application:** A Service Principal with Federated Identity Credentials (OIDC) mapped to the GitHub repository.
3. **Azure RBAC:** The Service Principal requires sufficient privileges (e.g., Contributor or specialized roles for ACR push, Container App modifications, and Network Reader).
4. **GitHub Environment:** Create a `development` environment in the repository settings to enable deployment approvals.

**Required Pipeline Permissions (`permissions` block):**
- `contents: read` — Clone the repository.
- `id-token: write` — Essential for OIDC authentication to Azure.
- `security-events: write` — Needed to upload Trivy SARIF results to the GitHub Security tab.

### 3.6 Database Operations

- **Backups:** Flexible Server provides automated daily backups with 35-day retention and Point-in-Time Restore (PITR)
- **Geo-redundant backups** enabled for production
- **Connection management:** Application uses `pg.Pool` (max 20 connections); PgBouncer at the DB level handles bursty traffic
- **Schema migrations:** In production, I would use a migration tool (e.g., `node-pg-migrate`) run as a pre-deploy step in the CI/CD pipeline
- **Scaling strategy:** As fleet size grows, the `fleet_pings` table should be partitioned by timestamp (monthly/weekly). Indexes on `vehicle_id` and `ts` should be added. Eventually, consider Azure Cosmos DB for PostgreSQL (Citus) for horizontal sharding.

### 3.7 Testing

Added a `server.test.js` suite (Jest + Supertest) covering `/health`, `/ready`, `/api/auth/login`,
and `/api/admin/drivers`. The `pg` client is mocked so the suite runs without a live database —
CI shouldn't need to provision Postgres just to lint request/response behavior. Coverage includes:

- `/health` returns 200 without touching the database
- `/ready` returns 200/503 based on whether the (mocked) DB query succeeds
- Login rejects missing input, rejects unknown phone numbers, and — importantly — asserts the
  query text contains `$1` and the raw phone number is passed as a bind parameter, not
  concatenated into the SQL string, which is the actual regression test for the SQL injection fix
- Login issues a JWT with an 8-hour expiry, verified by decoding it
- The admin endpoint rejects requests with no bearer token and accepts a valid one

This closes the gap where `"test": "jest --passWithNoTests"` made the CI "Test" stage a no-op
despite `jest`/`supertest` already being listed as devDependencies.

---

## 4. What I Chose Not to Change and Why

| Item | Reason |
|---|---|
| **OTP verification logic** | The assessment focuses on DevOps/infra. The placeholder OTP flow is adequate for demonstrating the architecture. |
| **API rate limiting** | Would add `express-rate-limit` in production, but the WAF policy provides basic protection at the edge. |
| **Database schema indexes** | The schema works; in production I'd add indexes on `fleet_pings(vehicle_id, ts)`, but schema optimization is out of scope. |
| **HTTPS certificate on AppGW** | Requires a real domain and certificate. The Terraform includes the HTTPS listener structure; a cert can be attached during actual deployment. |
| **Azure AD (Entra ID) authentication for PostgreSQL** | Ideal but adds complexity. Password-based auth via Key Vault is the pragmatic starting point. |

---

## 5. Security Approach

### Defense in Depth

1. **Edge:** Application Gateway WAF blocks OWASP Top 10 attacks
2. **Network:** All backend services (Container App, PostgreSQL, Key Vault, ACR) are private — no public endpoints
3. **Identity:** System-assigned Managed Identity for service-to-service auth; RBAC with least-privilege roles
4. **Application:** Parameterized queries, JWT authentication, input validation
5. **Secrets:** Key Vault with purge protection; no secrets in code, images, or environment files
6. **Supply chain:** Dependabot monitors dependencies; Trivy scans container images for CVEs
7. **Container:** Non-root user, minimal Alpine base, no SSH

---

## 6. Monitoring Approach

### Structured Logging
All application logs are JSON-formatted via Pino, streamed to Azure Log Analytics via Container Apps integration.

### Key Alerts (implemented in Terraform)

All alerts route to the `ag-ops-*` action group (email: ops@vexardrive.com).

| Alert | Trigger | Why It Matters |
|---|---|---|
| HTTP 5xx rate | >10 errors in 15 min | Indicates app crashes or unhandled errors |
| DB CPU | >80% for 15 min | Query contention or missing indexes |
| DB Storage | >85% usage | DB becomes read-only when full |
| DB Connections | >80 active | Connection leak or pool exhaustion |
| WAF blocked spike | >100 blocks in 15 min | Active attack or false-positive blocking |

Diagnostic settings send Application Gateway, PostgreSQL, and Key Vault logs to Log Analytics. Application Insights is wired to the Container App via `APPLICATIONINSIGHTS_CONNECTION_STRING`.

### Dashboards
Log Analytics and Application Insights provide built-in dashboards. Custom KQL queries can be created for fleet-specific metrics (e.g., pings per vehicle, geographic distribution).

---

## 7. Cost Considerations

| Component | Dev Cost (est.) | Prod Cost (est.) | Notes |
|---|---|---|---|
| Container Apps | ~$0 (scale to zero) | ~$100–200/mo | Consumption-based, 2 always-on replicas |
| PostgreSQL Flexible | ~$15/mo (B1ms) | ~$200/mo (D2s_v3 + HA) | HA doubles compute cost |
| Application Gateway + WAF | ~$180/mo | ~$180/mo | Fixed cost for WAF_v2 SKU |
| Key Vault | <$1/mo | <$1/mo | Per-operation pricing |
| ACR Premium | ~$170/mo | ~$170/mo | Required for private endpoint |
| Log Analytics | ~$5/mo | ~$20–50/mo | Based on data ingestion |

**Total estimate:** Dev ~$370/mo, Prod ~$700–800/mo

**Cost optimization opportunities:**
- Use ACR Basic ($5/mo) if private endpoint is not required (e.g., for dev)
- Use reserved instances for PostgreSQL (1-year commitment saves ~40%)
- Application Gateway cost is the largest fixed cost; consider Azure Front Door as an alternative if global distribution is needed

---

## 8. Assumptions and Constraints

- **No Azure subscription available** — Terraform is validated for correctness and reasoning, not deployed
- Fleet vehicles communicate over HTTPS (TLS 1.2+)
- The service handles moderate fleet sizes (hundreds to low thousands of vehicles)
- Single-region deployment is sufficient for now
- GitHub is the source control and CI/CD platform

---

## 9. Known Limitations

- **No TLS certificate** configured on Application Gateway (requires a domain)
- **OTP verification** is not implemented (placeholder)
- **No database migration tool** integrated (would use `node-pg-migrate` in production)
- **Test suite mocks the PostgreSQL client rather than exercising a real database** — it verifies
  request/response behavior and the parameterized-query shape, but a schema-level regression
  (e.g. a typo'd column name) wouldn't be caught by these tests alone
- **No load testing** performed (would use k6 or Artillery)
- **Schema lacks indexes** for high-volume query patterns
- **Single region** — no multi-region failover
- **Container replicas at max alert** — deferred; would require a custom metric or KQL alert in Log Analytics

---

## 10. What I Would Do Next With More Time

1. **Add database migrations** — Integrate `node-pg-migrate` into the CI/CD pipeline
2. **Expand test coverage** — The current suite (`server.test.js`) covers `/health`, `/ready`, login, and admin-auth against a mocked `pg` client; next step is integration tests against a real ephemeral test database (e.g. a Dockerized Postgres in CI, or `pg-mem`) to catch query/schema-level regressions the mock can't
3. **Implement proper OTP verification** — Time-limited codes via SMS (Twilio/Azure Communication Services)
4. **Add API rate limiting** — `express-rate-limit` at the app layer
5. **Add table indexes and partitioning** — `fleet_pings(vehicle_id, ts)` index; time-based partitioning
6. **Set up Azure Front Door** — Global load balancing if the fleet spans multiple regions
7. **Implement Entra ID auth for PostgreSQL** — Passwordless database authentication
8. **Add Terraform remote state** — Azure Storage backend with state locking
9. **Load testing** — Simulate fleet-scale traffic to validate scaling behavior
10. **Chaos engineering** — Test failure scenarios (DB failover, container crashes, network partitions)

---

## 11. AI Tool Usage Disclosure

AI tools (GitHub Copilot, Claude) were used during this assessment for:
- Code generation and refactoring assistance
- Terraform resource configuration reference
- Documentation drafting

All generated code was reviewed, understood, and validated by me. Engineering decisions and architectural choices reflect my own judgment.
