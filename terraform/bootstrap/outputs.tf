output "state_bucket" {
  description = "Put this in each stack's backend config (backend.hcl): bucket = \"...\"."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  value = var.region
}
