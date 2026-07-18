#!/usr/bin/env bash
# Chart-version skew across envs (issue #17). Per-env chart pins are deliberate
# — that's how promotion works — but forgotten envs aren't: this prints any
# component whose pinned targetRevision differs between gitops/envs/*, so
# "staging bumped, prod forgotten forever" is visible in every `make check`.
# Warning-only by default because skew is legitimate mid-promotion; set
# STRICT_CHART_SKEW=1 to fail on it (e.g. in a release branch).
set -euo pipefail

cd "$(dirname "$0")/.."

# Branch-tracking revisions aren't pins; everything else (chart versions,
# release tags) must eventually agree across the envs that ship the component.
# `|| true` guards: a file whose only targetRevision is a branch produces no
# pins, and that must not trip set -e/pipefail.
pins_in() {
  grep -h "targetRevision:" "$1" | awk '{print $2}' | tr -d '"' |
    { grep -v "^main$" || true; } | sort -u
}

skew=0
for f in $(find gitops/envs/*/apps -name "*.yaml" -exec basename {} \; | sort -u); do
  versions=$(for e in dev staging prod; do
    p="gitops/envs/$e/apps/$f"
    if [ -f "$p" ]; then pins_in "$p"; fi
  done | sort -u)
  count=$(printf '%s' "$versions" | { grep -c . || true; })
  if [ "$count" -gt 1 ]; then
    skew=1
    echo "SKEW ${f%.yaml}:"
    for e in dev staging prod; do
      p="gitops/envs/$e/apps/$f"
      if [ -f "$p" ]; then
        echo "  $e: $(pins_in "$p" | paste -sd, -)"
      fi
    done
  fi
done

if [ "$skew" -eq 0 ]; then
  echo "chart skew: pinned chart versions agree across envs"
elif [ "${STRICT_CHART_SKEW:-0}" = "1" ]; then
  echo "chart skew: divergent pins above (STRICT_CHART_SKEW=1) — finish the promotion"
  exit 1
else
  echo "chart skew: warning-only (legitimate mid-promotion); STRICT_CHART_SKEW=1 enforces"
fi
