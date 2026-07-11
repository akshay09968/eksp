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

if [ "$fail" = 0 ]; then
  echo "env parity: shared files identical (prod variables.tf exception is documented)"
fi
exit "$fail"
