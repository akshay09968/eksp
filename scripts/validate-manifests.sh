#!/usr/bin/env bash
# Validate every kustomize overlay and raw manifest dir against Kubernetes schemas.
# Strict on core objects; CRD kinds (Application, PrometheusRule, NodePool, ...)
# validate against the community CRDs-catalog (issue #14) — fetched over the
# network, so this needs egress; kinds missing from the catalog still skip via
# -ignore-missing-schemas rather than fail. No cluster needed. Used by `make
# kubeconform` and CI.
set -euo pipefail

cd "$(dirname "$0")/.."

KUBECONFORM_FLAGS=(-strict -ignore-missing-schemas -summary
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')

fail=0

echo "== kustomize overlays"
while IFS= read -r kfile; do
  dir="$(dirname "$kfile")"
  # bases and components can't build standalone — they're validated through
  # the overlays that include them (components/sso via the *-sso overlays)
  case "$dir" in
    */base | */components/*) continue ;;
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
