#!/usr/bin/env bash
# One-time personalization: point GitOps manifests and image references at YOUR
# fork/account. Run after `git push` and `make bootstrap`:
#
#   ./scripts/configure-repo.sh https://github.com/you/repo.git 123456789012.dkr.ecr.ap-south-1.amazonaws.com
#
set -euo pipefail

REPO_URL="${1:?usage: configure-repo.sh <git-https-url> <ecr-registry>}"
REGISTRY="${2:?usage: configure-repo.sh <git-https-url> <ecr-registry>}"

cd "$(dirname "$0")/.."

# Portable in-place sed: BSD (macOS) needs -i '', GNU needs -i (AUDIT P1-7).
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

PLACEHOLDER_REPO="https://github.com/akshay09968/eksp.git"
PLACEHOLDER_REGISTRY="000000000000.dkr.ecr.ap-south-1.amazonaws.com"

grep -rl "$PLACEHOLDER_REPO" gitops/ | while IFS= read -r f; do
  sedi "s|$PLACEHOLDER_REPO|$REPO_URL|g" "$f"
  echo "repo url  → $f"
done

grep -rl "$PLACEHOLDER_REGISTRY" gitops/ | while IFS= read -r f; do
  sedi "s|$PLACEHOLDER_REGISTRY|$REGISTRY|g" "$f"
  echo "registry  → $f"
done

# LB access-log bucket names embed the account id (COMPLIANCE #4). The account
# is the leading 12 digits of the ECR registry host; fill the placeholder.
ACCOUNT="${REGISTRY%%.*}"
if printf '%s' "$ACCOUNT" | grep -Eq '^[0-9]{12}$'; then
  grep -rl -- "-lb-logs-000000000000" gitops/ | while IFS= read -r f; do
    sedi "s|-lb-logs-000000000000|-lb-logs-${ACCOUNT}|g" "$f"
    echo "log bucket → $f"
  done
else
  echo "WARN: could not derive a 12-digit account id from '$REGISTRY' — set the"
  echo "      eksp-<env>-lb-logs-<account> bucket names in gitops/ by hand."
fi

echo
echo "Done. Review with 'git diff', commit, push — ArgoCD picks it up from there."
echo "Also set gitops_repo_url = \"$REPO_URL\" in terraform/envs/*/terraform.tfvars."
