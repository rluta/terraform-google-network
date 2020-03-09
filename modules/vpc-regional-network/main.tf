terraform {
  # This module has been updated with 0.12 syntax, which means it is no longer compatible with any versions below 0.12.
  required_version = ">= 0.12"
}

# ---------------------------------------------------------------------------------------------------------------------
# Create the Network & corresponding Router to attach other resources to
# Networks that preserve the default route are automatically enabled for Private Google Access to GCP services
# provided subnetworks each opt-in; in general, Private Google Access should be the default.
# ---------------------------------------------------------------------------------------------------------------------

data "google_compute_network" "vpc" {
  name = var.network
}

locals {
  network = data.google_compute_network.vpc.self_link
  short_region_name  = substr(var.region, 0 , 2)
  name_prefix = "${data.google_compute_network.vpc.name}-${local.short_region_name}"
}

resource "google_compute_router" "vpc_router" {
  name = "${local.name_prefix}-router"

  project = var.project
  region  = var.region
  network = var.network
}

# ---------------------------------------------------------------------------------------------------------------------
# Public Subnetwork Config
# Public internet access for instances with addresses is automatically configured by the default gateway for 0.0.0.0/0
# External access is configured with Cloud NAT, which subsumes egress traffic for instances without external addresses
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_subnetwork" "vpc_subnetwork_public" {
  name = "${local.name_prefix}-subnetwork-public"

  project = var.project
  region  = var.region
  network = local.network

  private_ip_google_access = true
  ip_cidr_range            = cidrsubnet(var.cidr_block, var.cidr_subnetwork_width_delta, 0)

  secondary_ip_range {
    range_name = "public-services"
    ip_cidr_range = cidrsubnet(
      var.secondary_cidr_block,
      var.secondary_cidr_subnetwork_width_delta,
      0
    )
  }
}

resource "google_compute_router_nat" "vpc_nat" {
  name = "${local.name_prefix}-nat"

  project = var.project
  region  = var.region
  router  = google_compute_router.vpc_router.name

  nat_ip_allocate_option = "AUTO_ONLY"

  # "Manually" define the subnetworks for which the NAT is used, so that we can exclude the public subnetwork
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.vpc_subnetwork_public.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Private Subnetwork Config
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_subnetwork" "vpc_subnetwork_private" {
  name = "${local.name_prefix}-subnetwork-private"

  project = var.project
  region  = var.region
  network = local.network

  private_ip_google_access = true
  ip_cidr_range = cidrsubnet(
    var.cidr_block,
    var.cidr_subnetwork_width_delta,
    1 * (1 + var.cidr_subnetwork_spacing)
  )

  secondary_ip_range {
    range_name = "private-services"
    ip_cidr_range = cidrsubnet(
      var.secondary_cidr_block,
      var.secondary_cidr_subnetwork_width_delta,
      1 * (1 + var.secondary_cidr_subnetwork_spacing)
    )
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Attach Firewall Rules to allow inbound traffic to tagged instances
# ---------------------------------------------------------------------------------------------------------------------

module "network_firewall" {
  source = "../network-firewall"

  name_prefix = local.name_prefix

  project                               = var.project
  network                               = local.network
  allowed_public_restricted_subnetworks = var.allowed_public_restricted_subnetworks

  public_subnetwork  = google_compute_subnetwork.vpc_subnetwork_public.self_link
  private_subnetwork = google_compute_subnetwork.vpc_subnetwork_private.self_link
}

