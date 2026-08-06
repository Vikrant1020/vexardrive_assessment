#!/bin/bash
set -e

# ──────────────────────────────────────────────
# clean.sh — Format, validate, and clean up
#             Terraform project artifacts.
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/env"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Terraform Format / Validate / Clean   ${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"

# ── Step 1: Format all .tf files recursively ──
echo ""
echo -e "${GREEN}[1/3] Formatting all Terraform files...${NC}"
terraform -chdir="${SCRIPT_DIR}" fmt -recursive
echo -e "${GREEN}  ✔ Formatting complete.${NC}"

# ── Step 2: Validate each environment ──
echo ""
echo -e "${GREEN}[2/3] Validating Terraform configurations...${NC}"

ERRORS=0
for env_path in "${ENV_DIR}"/*/; do
  env_name=$(basename "${env_path}")
  echo -n "  • ${env_name}: "

  # Init (backend disabled) so providers/modules are available for validation
  if terraform -chdir="${env_path}" init -backend=false -input=false -no-color > /dev/null 2>&1; then
    # Validate
    if terraform -chdir="${env_path}" validate -no-color > /dev/null 2>&1; then
      echo -e "${GREEN}✔ valid${NC}"
    else
      echo -e "${RED}✖ validation failed${NC}"
      terraform -chdir="${env_path}" validate -no-color 2>&1 | sed 's/^/    /'
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo -e "${RED}✖ init failed${NC}"
    terraform -chdir="${env_path}" init -backend=false -input=false -no-color 2>&1 | sed 's/^/    /'
    ERRORS=$((ERRORS + 1))
  fi
done

if [ "${ERRORS}" -gt 0 ]; then
  echo ""
  echo -e "${RED}  ✖ ${ERRORS} environment(s) had errors.${NC}"
  exit 1
fi
echo -e "${GREEN}  ✔ All environments valid.${NC}"

# ── Step 3: Remove local state and lock files ──
echo ""
echo -e "${GREEN}[3/3] Cleaning up local artifacts...${NC}"
find "${SCRIPT_DIR}" -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
find "${SCRIPT_DIR}" -name "*.tfstate" -delete 2>/dev/null || true
find "${SCRIPT_DIR}" -name "*.tfstate.backup" -delete 2>/dev/null || true
echo -e "${GREEN}  ✔ Cleanup complete.${NC}"

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  All done!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
