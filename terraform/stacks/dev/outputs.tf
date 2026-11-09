output "app_public_ip" {
  description = "The static IP (Elastic IP) of the dev environment."
  value       = module.app.public_ip
}

output "app_private_ip" {
  value = module.app.private_ip
}

output "app_instance_id" {
  value = module.app.instance_id
}

output "base_domain" {
  value = local.base_domain
}

output "api_url" {
  description = "EXPO_PUBLIC_API_BASE_URL for the apps."
  value       = "https://api.${local.base_domain}"
}

output "app_urls" {
  value = {
    customer   = "https://app.${local.base_domain}"
    driver     = "https://driver.${local.base_domain}"
    restaurant = "https://restaurant.${local.base_domain}"
  }
}

output "media_bucket" {
  value = module.storage.media_bucket
}

output "documents_bucket" {
  value = module.storage.documents_bucket
}

output "ssh" {
  value = "ssh ubuntu@${module.app.public_ip}"
}
