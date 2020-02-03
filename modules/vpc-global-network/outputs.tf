output "network" {
  description = "A self-link reference to VPC network"
  value       = google_compute_network.vpc.self_link
}

output "network_name" {
  description = "the VPC network name"
  value       = google_compute_network.vpc.name
}

output "name_prefix" {
  description = "A prefix tied to this network that guarantees uniqueness in the project"
  value       = var.name_prefix
}
