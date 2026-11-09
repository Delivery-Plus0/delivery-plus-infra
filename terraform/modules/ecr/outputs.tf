output "registry" {
  description = "Registry host for docker login and image names: <account>.dkr.ecr.<region>.amazonaws.com."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "repository_arns" {
  value = [for repo in aws_ecr_repository.this : repo.arn]
}

output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}
