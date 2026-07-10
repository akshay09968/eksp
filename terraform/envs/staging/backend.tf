# Partial configuration — bucket/key/region/use_lockfile are injected by
# `make init ENV=dev` (bucket name derives from the account id; created by
# terraform/bootstrap). S3-native locking, no DynamoDB (ADR-0008).
terraform {
  backend "s3" {}
}
