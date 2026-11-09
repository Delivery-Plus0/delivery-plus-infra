# The backend's two buckets, set up as docs/deployment.md in the backend asks:
#
# - media (AWS_S3_BUCKET): profile, restaurant and menu photos. Checked images are public-read under
#   their final prefixes; uploads land in pending/ first and expire after a day if never confirmed.
# - documents (DRIVER_DOCUMENTS_BUCKET, #207): driver documents. Fully private: Block Public Access
#   on, no bucket policy grants anyone, and the app role may only touch pending/drivers/* and drivers/*.
#
# Browsers upload straight to S3 with presigned POSTs, so each bucket has CORS for the app origins.

locals {
  media_name     = "${var.name}-media-${var.account_id}"
  documents_name = "${var.name}-documents-${var.account_id}"

  # Derived from the names (an S3 ARN is just arn:aws:s3:::<bucket>), so the policies are known at
  # plan time and testable without AWS.
  media_arn     = "arn:aws:s3:::${local.media_name}"
  documents_arn = "arn:aws:s3:::${local.documents_name}"
}

# ---------------------------------------------------------------------------------------------
# Media bucket
# ---------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "media" {
  bucket        = local.media_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ACLs stay blocked; only the bucket policy below makes the final image prefixes readable.
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "media" {
  statement {
    sid       = "PublicReadCheckedImages"
    actions   = ["s3:GetObject"]
    resources = [for prefix in var.media_public_prefixes : "${local.media_arn}/${prefix}*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.media_arn, "${local.media_arn}/*"]

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

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = data.aws_iam_policy_document.media.json

  depends_on = [aws_s3_bucket_public_access_block.media]
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_methods = ["POST", "PUT", "GET", "HEAD"]
    allowed_origins = var.app_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "expire-unconfirmed-uploads"
    status = "Enabled"

    filter {
      prefix = "pending/"
    }

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ---------------------------------------------------------------------------------------------
# Driver documents bucket (private)
# ---------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "documents" {
  bucket        = local.documents_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "documents" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.documents_arn, "${local.documents_arn}/*"]

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

resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  policy = data.aws_iam_policy_document.documents.json

  depends_on = [aws_s3_bucket_public_access_block.documents]
}

# Only the driver app uploads documents.
resource "aws_s3_bucket_cors_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  cors_rule {
    allowed_methods = ["POST"]
    allowed_origins = var.document_upload_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "expire-unconfirmed-uploads"
    status = "Enabled"

    filter {
      prefix = "pending/"
    }

    expiration {
      days = 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = "drivers/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.documents]
}

# ---------------------------------------------------------------------------------------------
# What the services may do (attached to the app host's role)
# ---------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "app_access" {
  # Media: presigned uploads into pending/, then a checked copy to the final prefix.
  statement {
    sid     = "MediaObjects"
    actions = ["s3:PutObject", "s3:GetObject"]
    resources = concat(
      ["${local.media_arn}/pending/*"],
      [for prefix in var.media_public_prefixes : "${local.media_arn}/${prefix}*"],
    )
  }

  # Driver documents (#207): exactly these two prefixes, nothing else in the bucket.
  statement {
    sid     = "DriverDocuments"
    actions = ["s3:PutObject", "s3:GetObject"]
    resources = [
      "${local.documents_arn}/pending/drivers/*",
      "${local.documents_arn}/drivers/*",
    ]
  }

  # A confirm on an upload that never arrived must read as 404 (the services check for it), which
  # S3 only returns with ListBucket. Scoped to the pending/ prefix of each bucket.
  statement {
    sid       = "ListPendingUploads"
    actions   = ["s3:ListBucket"]
    resources = [local.media_arn, local.documents_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["pending/*"]
    }
  }
}
