#!/usr/bin/env bash
# ADR-0002 accepts env duplication; it does not accept *unnoticed* divergence
# (AUDIT P1-8). Shared plumbing files must stay identical across envs; the
# deliberate exceptions are listed here explicitly.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# Identical everywhere: the plumbing.
for f in versions.tf backend.tf providers.tf outputs.tf; do
  for env in staging prod; do
    if ! cmp -s "terraform/envs/dev/$f" "terraform/envs/$env/$f"; then
      echo "DIVERGED: terraform/envs/$env/$f differs from dev/$f — if deliberate, update this script's exception list"
      fail=1
    fi
  done
done

# variables.tf: dev == staging; prod deliberately differs (endpoint CIDRs have
# no default + a validation block, per the security review).
if ! cmp -s terraform/envs/dev/variables.tf terraform/envs/staging/variables.tf; then
  echo "DIVERGED: staging/variables.tf differs from dev — not on the exception list"
  fail=1
fi

# NodeLocal DNSCache guard (AUDIT P1-9 / issue #3): the prod manifest hardcodes
# kube-dns ClusterIP 172.20.0.10, which is only true because EKS picks service
# CIDR 172.20.0.0/16 when the VPC lives in 10.0.0.0/8. A VPC outside 10/8 would
# silently break DNS interception in prod — fail here instead.
for env_main in terraform/envs/*/main.tf; do
  cidr=$(grep -Eo 'vpc_cidr\s*=\s*"[0-9./]+"' "$env_main" | grep -Eo '"[0-9./]+"' | tr -d '"')
  case "$cidr" in
    10.*) : ;;
    "")
      echo "GUARD: no vpc_cidr literal found in $env_main — update this guard if the shape changed"
      fail=1
      ;;
    *)
      echo "GUARD: $env_main uses vpc_cidr $cidr (outside 10/8) — EKS will NOT pick 172.20.0.0/16, so gitops/platform/overlays/prod/nodelocal-dns.yaml's hardcoded 172.20.0.10 breaks. Fix the manifest or the CIDR."
      fail=1
      ;;
  esac
done

if [ "$fail" = 0 ]; then
  echo "env parity: shared files identical (prod variables.tf exception is documented)"
  echo "nodelocal guard: all env VPCs in 10/8 (172.20.0.10 assumption holds)"
fi
exit "$fail"
