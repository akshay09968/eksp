#!/usr/bin/env bash
# One-time personalization: point GitOps manifests and image references at YOUR
# fork/account. Run after `git push` and `make bootstrap`:
#
#   ./scripts/configure-repo.sh https://github.com/you/repo.git 123456789012.dkr.ecr.ap-south-1.amazonaws.com [github-org github-team]
#
# The optional org/team pair fills the GitHub SSO placeholders (ADR-0019,
# docs/RUNBOOK.md#github-sso) — omit them to leave SSO unconfigured.
set -euo pipefail

REPO_URL="${1:?usage: configure-repo.sh <git-https-url> <ecr-registry> [github-org github-team]}"
REGISTRY="${2:?usage: configure-repo.sh <git-https-url> <ecr-registry> [github-org github-team]}"
GITHUB_ORG="${3:-}"
GITHUB_TEAM="${4:-}"

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

# GitHub SSO placeholders (Grafana values + oauth2-proxy args). ADMIN-TEAM is
# replaced first so the '@ORG/TEAM' role mapping never half-matches.
if [ -n "$GITHUB_ORG" ] && [ -n "$GITHUB_TEAM" ]; then
  grep -rl -- "GITHUB-SSO-" gitops/ | while IFS= read -r f; do
    sedi "s|GITHUB-SSO-ADMIN-TEAM|${GITHUB_TEAM}|g; s|GITHUB-SSO-ORG|${GITHUB_ORG}|g" "$f"
    echo "sso org/team → $f"
  done
elif [ -n "$GITHUB_ORG" ]; then
  echo "WARN: github-org given without github-team — SSO placeholders left alone."
fi

echo
echo "Done. Review with 'git diff', commit, push — ArgoCD picks it up from there."
echo "Also set gitops_repo_url = \"$REPO_URL\" in terraform/envs/*/terraform.tfvars."
if [ -n "$GITHUB_ORG" ]; then
  echo "And for SSO: github_sso_org/github_sso_admin_team in the same tfvars +"
  echo "the Secrets from docs/RUNBOOK.md#github-sso."
fi
