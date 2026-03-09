terraform {
  required_version = ">= 1.4"

  required_providers {
    harvester = {
      source  = "registry.terraform.io/harvester/harvester"
      version = ">= 0.6.4"
    }
  }
}

# -----------------------------------------------------------------------------
# Example: have Harvester download an image from a URL.
#
# Run this first, then use examples/vm/ to create a VM from the downloaded image.
#
# Prerequisites:
#   - A kubeconfig file with access to your Harvester cluster
#   - The URL must be reachable from the Harvester cluster nodes
# -----------------------------------------------------------------------------

module "image" {
  source = "../../image"

  kubeconfig_path    = "/path/to/harvester-kubeconfig.yaml"
  image_source       = "download"
  image_name         = "opensuse-leap-15-6"
  image_namespace    = "harvester-public"
  image_display_name = "openSUSE Leap 15.6"
  image_url          = "https://downloadcontent-us1.opensuse.org/repositories/Cloud:/Images:/Leap_15.6/images/openSUSE-Leap-15.6.x86_64-NoCloud.qcow2"
}

output "image_id"        { value = module.image.image_id }
output "image_name"      { value = module.image.image_name }
output "image_namespace" { value = module.image.image_namespace }
output "image_state"     { value = module.image.image_state }
