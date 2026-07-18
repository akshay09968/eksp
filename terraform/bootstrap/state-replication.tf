# State-bucket DR (issue #18): cross-region replication of every state object
# version. The state bucket is the one thing in this repo that is not
# reconstructible from git — losing it means re-importing the world. Everything
# else has a rebuild path (cluster from terraform, workloads from ArgoCD).
#
# CMKs, not the aws/s3 managed key: S3 replication cannot replicate objects
# encrypted with the AWS-managed key, so the state bucket's SSE uses
# aws_kms_key.tf_state (main.tf) and replicas re-encrypt with the replica-region
# key below.

resource "aws_kms_key" "tf_state" {
  description         = "eksp terraform state (CMK: the aws/s3 managed key cannot replicate)"
  enable_key_rotation = true
}

resource "aws_kms_alias" "tf_state" {
  name          = "alias/eksp-tf-state"
  target_key_id = aws_kms_key.tf_state.key_id
}

resource "aws_kms_key" "tf_state_replica" {
  provider = aws.replica

  description         = "eksp terraform state replicas (${var.state_replica_region})"
  enable_key_rotation = true
}

resource "aws_kms_alias" "tf_state_replica" {
  provider = aws.replica

  name          = "alias/eksp-tf-state-replica"
  target_key_id = aws_kms_key.tf_state_replica.key_id
}

# --- Replica bucket: same posture as the source (versioned, CMK, TLS-only,
#     public-blocked, noncurrent expiry).

resource "aws_s3_bucket" "tf_state_replica" {
  provider = aws.replica

  bucket = "eksp-tfstate-replica-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.tf_state_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.tf_state_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tf_state_replica.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state_replica" {
  provider = aws.replica

  bucket                  = aws_s3_bucket.tf_state_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tf_state_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.tf_state_replica.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "tf_state_replica_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state_replica.arn,
      "${aws_s3_bucket.tf_state_replica.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tf_state_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.tf_state_replica.id
  policy = data.aws_iam_policy_document.tf_state_replica_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.tf_state_replica]
}

# --- Replication role: scoped to exactly this source→destination pair.

data "aws_iam_policy_document" "replication_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replication" {
  statement {
    sid = "ReadSource"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.tf_state.arn]
  }

  statement {
    sid = "ReadSourceVersions"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.tf_state.arn}/*"]
  }

  statement {
    sid = "WriteReplica"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.tf_state_replica.arn}/*"]
  }

  statement {
    sid       = "DecryptSource"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.tf_state.arn]
  }

  statement {
    sid = "EncryptReplica"
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.tf_state_replica.arn]
  }
}

resource "aws_iam_role" "state_replication" {
  name               = "eksp-tfstate-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

resource "aws_iam_role_policy" "state_replication" {
  name   = "replicate-tf-state"
  role   = aws_iam_role.state_replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  role   = aws_iam_role.state_replication.arn

  rule {
    id     = "state-dr"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    # Without this, SSE-KMS objects — i.e. every state file — are silently
    # skipped by replication.
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket = aws_s3_bucket.tf_state_replica.arn

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.tf_state_replica.arn
      }
    }
  }

  # Replication requires versioning active on both ends first.
  depends_on = [
    aws_s3_bucket_versioning.tf_state,
    aws_s3_bucket_versioning.tf_state_replica,
  ]
}
