output "media_bucket" {
  value = aws_s3_bucket.media.bucket
}

output "documents_bucket" {
  value = aws_s3_bucket.documents.bucket
}

output "media_public_base_url" {
  description = "AWS_PUBLIC_BASE_URL: where confirmed images are read from."
  value       = "https://${aws_s3_bucket.media.bucket_regional_domain_name}"
}

output "app_access_policy_json" {
  description = "IAM policy for the services' S3 access; attach to the app host role."
  value       = data.aws_iam_policy_document.app_access.json
}
