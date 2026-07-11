#!/usr/bin/env bash
# Cross-layer guard (AUDIT coverage gap): an ArgoCD Application whose `path:`
# or `$values/` reference points at a renamed/deleted directory passes
# kubeconform (it's valid YAML) but breaks sync in the cluster. Fail it here.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# `path: <repo-relative-dir>` in Applications that source *this* repo.
while IFS=: read -r file _ path; do
  path="$(echo "$path" | tr -d ' "')"
  # Only paths that are meant to exist in this repo (skip upstream repos'
  # paths like config/crd/standard from kubernetes-sigs/gateway-api).
  case "$path" in
    gitops/*|apps/*|terraform/*)
      if [ ! -d "$path" ]; then
        echo "MISSING DIR: $path (referenced by $file)"
        fail=1
      fi
      ;;
  esac
done < <(grep -rn --include='*.yaml' '^\s*path:' gitops/envs/)

# `$values/<file>` references in multi-source Applications.
while IFS=: read -r file _ ref; do
  rel="$(echo "$ref" | tr -d ' "' | sed 's|^-\$values/||')"
  if [ ! -f "$rel" ]; then
    echo "MISSING FILE: $rel (referenced by $file)"
    fail=1
  fi
done < <(grep -rn --include='*.yaml' -- '- \$values/' gitops/envs/)

if [ "$fail" = 0 ]; then
  echo "gitops path references: all resolve"
fi
exit "$fail"
