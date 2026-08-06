# Improvements Needed — Pre-Submission Checklist

Tracked from a full review of the codebase against the assessment brief. Grouped by priority. Check items off as they're fixed and verified (not just edited — actually run/test where possible).

---

## P0 — Must fix before submitting

- [ ] **Container port mismatch will break the deployment.**
  `server.js` / Dockerfile / `docker-compose.yml` all listen on `PORT=3000`, but
  `azure-infrastructure/env/dev/main.tf` sets `target_port = 80` on the Container App module.
  Nothing listens on 80 inside the container, so ingress would return 502s.
  **Fix:** change `target_port = 80` → `target_port = 3000` in `env/dev/main.tf`.

- [x] **Terraform/CI-CD ownership conflict on the container image.**
  The pipeline deploys new images via `azure/container-apps-deploy-action` (a direct `az` CLI call),
  bypassing Terraform entirely. `container_app/main.tf` has no `lifecycle` block, so the next
  `terraform apply` will revert the running app to whatever image is in Terraform state
  (likely the `nginx:latest` placeholder default), undoing every CI deploy.
  **Fix:** add `lifecycle { ignore_changes = [template[0].container[0].image] }` to the
  `azurerm_container_app` resource, or manage the image exclusively through Terraform instead
  of a separate `az` step — pick one and document it.
  **Done:** added the `lifecycle { ignore_changes = [template[0].container[0].image] }` block to
  `modules/backend/container_app/main.tf`.

- [ ] **Login endpoint has no real authentication.**
  `POST /api/auth/login` issues a valid 8h JWT for *any* phone number found in `drivers`,
  with no OTP/password check. Currently listed as a soft "known limitation" — this is a P0
  auth bypass (anyone who knows/guesses a driver's phone number gets a token, including
  access to `/api/admin/drivers` which dumps all driver PII).
  **Fix (minimum viable):** add a hardcoded/env-configurable OTP check for the assessment scope,
  and re-classify this explicitly as a P0 finding in the report rather than a shrugged-off limitation.

- [x] **"Test" stage in CI/CD tests nothing.**
  `package.json` → `"test": "jest --passWithNoTests"`, and there are no `*.test.js` files anywhere,
  despite `jest`/`supertest` being installed as devDependencies. The brief explicitly asks for a
  `Test → Build → Security Scan → ...` pipeline.
  **Fix:** add a minimal test suite — at least `/health`, `/ready`, and login with a parameterized
  query — using supertest against the Express app.
  **Done:** added `server.test.js` (Jest + Supertest, mocked `pg`) covering `/health`, `/ready`,
  login (including a direct assertion that the query is parameterized), and admin-route auth.
  Added a `**/*.test.js` override to `eslint.config.js` for Jest globals, exported `server` from
  `server.js` for clean teardown, and added `--forceExit` to the test script. **Not yet run** —
  no Node.js available in the environment this was written in; run `npm test` to confirm before
  committing.

- [ ] **README Terraform quick-start references variables that don't exist.**
  `README.md` tells the reader to run `terraform plan -var="tenant_id=..." -var="deployer_object_id=..." -var="db_admin_password=..."`,
  but `env/dev/variables.tf` has no such variables — tenant/object id come from
  `data.azurerm_client_config`, and the DB password is auto-generated via `random_password`.
  Following the README as written fails immediately.
  **Fix:** rewrite the quick-start section to match the actual variables (`project_name`,
  `environment`, `location`, `jwt_secret`, etc.).

---

## P1 — Should fix (real gaps against the brief)

- [ ] **No `env/prod/` exists.** The technical report claims "environment separation via tfvars —
  dev scales to zero, prod runs always-on with HA," but only `env/dev/` exists, and there are no
  `.tfvars`/`.tfvars.example` files at all (all gitignored, none committed as templates).
  **Fix:** either add a skeleton `env/prod/` with different `sku_name`/`ha_mode`/replica counts,
  or soften the report's claim to match what's actually implemented.

- [ ] **NSGs only cover the Application Gateway subnet.** The Container Apps subnet, DB subnet,
  and private-endpoint subnet have no NSG (`env/dev/main.tf` only wires `module.nsg_assoc` to
  `subnet_appgw`). Relying solely on delegation + private endpoints is workable but not
  defense-in-depth.
  **Fix:** add NSGs with explicit allow rules for required flows (e.g., Container Apps subnet →
  DB subnet on 5432, → Key Vault/ACR private endpoints) and deny-by-default otherwise. If skipping
  this intentionally, say so explicitly in the report.

- [ ] **No least-privilege database role for the app.** The app connects to Postgres as the admin
  user (`vexaradmin`) for all queries, including the high-frequency ping insert. `schema.sql`
  creates tables but no role.
  **Fix:** add a `fleet_app` role with `INSERT`/`SELECT` only on the two tables, wire it into
  Terraform (new Key Vault secret + Container App env var), and stop using the admin credential
  for app traffic.

- [x] **Inconsistent secret provisioning pattern.** DB admin password is auto-generated by Terraform
  (`random_password` → Key Vault). `jwt_secret` is a plain sensitive input variable someone has to
  generate and pass manually, risking shell-history/CI-log leakage.
  **Fix:** generate `jwt_secret` the same way as the DB password (`random_password` resource →
  Key Vault secret) instead of taking it as a manual `-var`.
  **Done:** added `resource "random_password" "jwt_secret"` in `env/dev/main.tf`, wired it into
  `module.secret_jwt`, removed the `jwt_secret` variable from `variables.tf`, and added the
  `random` provider to `provider.tf`'s `required_providers`. Note: `README.md`'s quick-start still
  passes `-var="jwt_secret=..."` — that's now stale (out of scope for this pass, flagging here).

- [ ] **No input range/type validation on `/api/fleet/ping`.** Only checks that `vehicleId`/`lat`/`lng`
  are present, not that they're plausible values (lat ∈ [-90,90], lng ∈ [-180,180], numeric types).
  **Fix:** add basic range/type validation before the insert.

---

## P2 — Polish / lower risk

- [ ] **Rollback logic assumes ≥2 revisions exist.** In `.github/workflows/ci-cd.yml`, the rollback
  step does `sort_by([?properties.active], &properties.createdTime)[-2]`. On the very first deploy
  this is empty and `xargs` silently no-ops instead of alerting anyone that rollback failed.
  **Fix:** guard with a check for revision count and fail loudly (or skip with a clear log line) if
  there's nothing to roll back to.

- [ ] **`docker-compose.yml` has real-looking default credentials baked in**
  (`vexaradmin`/`vexaradmin`, `supersecretjwtkey` via `${VAR:-default}`). Fine for local dev, but
  worth a comment warning these must never be reused in a shared/staging compose file.

- [ ] **Comments narrate the diff instead of explaining the "why."** Several comments in `server.js`
  read like changelog entries (`// Reduced from 30d to 8h for security`, `// Fixed SQL injection`)
  rather than explaining a non-obvious constraint. Trim these down to what would still make sense
  to someone with no idea what the "before" state was.

- [ ] **No per-device/API-key auth or rate limit on `/api/fleet/ping`.** Reasonable to defer given
  WAF at the edge, but it's currently not mentioned anywhere in "known limitations" — add a line
  acknowledging it explicitly.

---

## Process — do this regardless of code changes

- [ ] **Build a real commit history.** Right now the only two commits in git (`Initial commit`,
  `Fleet Ping Service - v0`) are authored by `VexarDrive-Careers` and contain only the original
  starter files. Every fix, the entire Terraform tree, CI/CD workflow, and docs are currently
  **uncommitted working-tree changes** under nobody's name. Before submitting:
  1. Go through the changes area by area (app fixes → Docker → networking module → compute/KV/identity
     → CI/CD → docs).
  2. For each area, actually re-verify it (run `docker compose up`, `npm run lint`, `terraform validate`,
     etc.) and fix anything you find — this is also how the `target_port` bug and the README
     mismatch above should get caught.
  3. Commit each area separately, authored by you, with a message describing what was verified.

  This isn't about hiding AI assistance — the report's AI-disclosure section should stay and stay
  accurate. It's about the repo actually reflecting a real review process, and about you being able
  to defend every decision live, since that's explicitly part of the evaluation.

- [x] **Re-read the whole report after the above fixes land** and update anything that no longer
  matches reality (the P1 items above touch claims already made in `docs/TECHNICAL_REPORT.md`).
  **Done:** updated section 3.4 (secret generation + image lifecycle bullets), added section 3.7
  (Testing), updated the "known limitations" list (mocked-DB test caveat), and updated the
  "what I'd do next" item on tests to reflect the current suite instead of "no tests exist."
