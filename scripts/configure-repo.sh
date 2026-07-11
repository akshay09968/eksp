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

PLACEHOLDER_REPO="https://github.com/akshay09968/eksp.git"
PLACEHOLDER_REGISTRY="000000000000.dkr.ecr.ap-south-1.amazonaws.com"

grep -rl "$PLACEHOLDER_REPO" gitops/ | while IFS= read -r f; do
  sed -i '' "s|$PLACEHOLDER_REPO|$REPO_URL|g" "$f"
  echo "repo url  → $f"
done

grep -rl "$PLACEHOLDER_REGISTRY" gitops/ | while IFS= read -r f; do
  sed -i '' "s|$PLACEHOLDER_REGISTRY|$REGISTRY|g" "$f"
  echo "registry  → $f"
done

echo
echo "Done. Review with 'git diff', commit, push — ArgoCD picks it up from there."
echo "Also set gitops_repo_url = \"$REPO_URL\" in terraform/envs/*/terraform.tfvars."
