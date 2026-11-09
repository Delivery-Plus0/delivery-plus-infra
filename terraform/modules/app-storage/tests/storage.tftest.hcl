# Plan-only tests with the real AWS provider and fake credentials: the IAM policy documents are
# rendered for real, so their contents can be checked.

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

variables {
  name                    = "delivery-plus-dev"
  account_id              = "123456789012"
  app_origins             = ["https://app.203-0-113-10.sslip.io", "https://driver.203-0-113-10.sslip.io"]
  document_upload_origins = ["https://driver.203-0-113-10.sslip.io"]
}

run "bucket_names" {
  command = plan

  assert {
    condition     = output.media_bucket == "delivery-plus-dev-media-123456789012" && output.documents_bucket == "delivery-plus-dev-documents-123456789012"
    error_message = "Bucket names are <name>-<purpose>-<account>."
  }
}

run "documents_bucket_is_private" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.documents.block_public_acls,
      aws_s3_bucket_public_access_block.documents.block_public_policy,
      aws_s3_bucket_public_access_block.documents.ignore_public_acls,
      aws_s3_bucket_public_access_block.documents.restrict_public_buckets,
    ])
    error_message = "Driver documents (#207): Block Public Access fully on."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.documents.json).Statement : statement.Effect == "Deny"
    ])
    error_message = "The documents bucket policy grants nobody anything (it only denies insecure transport)."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.documents.cors_rule).allowed_methods == toset(["POST"])
    error_message = "Only presigned POST uploads from the driver app reach the documents bucket."
  }
}

run "media_public_only_after_confirmation" {
  command = plan

  assert {
    condition = alltrue([
      for resource in flatten([jsondecode(data.aws_iam_policy_document.media.json).Statement[0].Resource]) :
      !strcontains(resource, "pending")
    ])
    error_message = "Unconfirmed uploads (pending/) are never public."
  }

  assert {
    condition     = one([for rule in aws_s3_bucket_lifecycle_configuration.media.rule : rule.filter[0].prefix if rule.id == "expire-unconfirmed-uploads"]) == "pending/"
    error_message = "pending/ uploads expire."
  }
}

run "app_role_document_scope" {
  command = plan

  assert {
    condition = toset(flatten([
      for statement in jsondecode(data.aws_iam_policy_document.app_access.json).Statement : statement.Resource if statement.Sid == "DriverDocuments"
      ])) == toset([
      "arn:aws:s3:::delivery-plus-dev-documents-123456789012/pending/drivers/*",
      "arn:aws:s3:::delivery-plus-dev-documents-123456789012/drivers/*",
    ])
    error_message = "driver-service touches only pending/drivers/* and drivers/* in the documents bucket."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.app_access.json).Statement :
      !contains(flatten([statement.Action]), "s3:DeleteObject")
    ])
    error_message = "The services never delete objects (expiry is S3 lifecycle's job)."
  }
}

run "rejects_pending_as_public_prefix" {
  command = plan

  variables {
    media_public_prefixes = ["users/", "pending/"]
  }

  expect_failures = [var.media_public_prefixes]
}

run "rejects_origin_with_path" {
  command = plan

  variables {
    app_origins = ["https://app.example.com/home"]
  }

  expect_failures = [var.app_origins]
}
