# prod overrides. Sizing lives in main.tf — these are the user-specific knobs.

# region = "us-east-1"

# REQUIRED in prod (no default, 0.0.0.0/0 rejected) — your office/VPN CIDRs:
endpoint_public_access_cidrs = ["203.0.113.7/32"]

# gitops_repo_url = "https://github.com/<you>/<repo>.git"
