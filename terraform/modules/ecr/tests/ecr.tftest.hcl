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
  prefix   = "delivery-plus"
  services = ["api-gateway", "auth-service"]
}

run "immutable_scanned_repositories" {
  command = plan

  assert {
    condition     = toset(keys(aws_ecr_repository.this)) == toset(["api-gateway", "auth-service"])
    error_message = "One repository per service."
  }

  assert {
    condition     = alltrue([for repo in aws_ecr_repository.this : repo.image_tag_mutability == "IMMUTABLE" && repo.image_scanning_configuration[0].scan_on_push])
    error_message = "Tags are immutable (a tag is one commit) and images are scanned on push."
  }

  assert {
    condition     = aws_ecr_repository.this["api-gateway"].name == "delivery-plus/api-gateway"
    error_message = "Repositories are <prefix>/<service>."
  }
}

run "rejects_duplicate_services" {
  command = plan

  variables {
    services = ["api-gateway", "api-gateway"]
  }

  expect_failures = [var.services]
}
