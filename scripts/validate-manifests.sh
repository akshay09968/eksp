#!/usr/bin/env bash
# Validate every kustomize overlay and raw manifest dir against Kubernetes schemas.
# Strict on core objects; CRD kinds (Application, PrometheusRule, NodePool, ...) are
# skipped via -ignore-missing-schemas. Offline, no cluster needed. Used by `make
# kubeconform` and CI.
set -euo pipefail

cd "$(dirname "$0")/.."

KUBECONFORM_FLAGS=(-strict -ignore-missing-schemas -summary
  -schema-location default)

fail=0

echo "== kustomize overlays"
while IFS= read -r kfile; do
  dir="$(dirname "$kfile")"
  # bases are validated through their overlays
  case "$dir" in
    */base) continue ;;
  esac
  echo "-- $dir"
  if ! kustomize build "$dir" | kubeconform "${KUBECONFORM_FLAGS[@]}"; then
    fail=1
  fi
done < <(find gitops -name kustomization.yaml | sort)

echo "== raw manifest dirs (ArgoCD Applications)"
for dir in gitops/envs/*/apps; do
  echo "-- $dir"
  if ! kubeconform "${KUBECONFORM_FLAGS[@]}" "$dir"; then
    fail=1
  fi
done

echo "== cross-layer: Application path references resolve"
if ! ./scripts/check-gitops-paths.sh; then
  fail=1
fi

exit "$fail"
