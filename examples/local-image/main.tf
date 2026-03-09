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
# Example: upload a local image to Harvester.
#
# Run this first, then use examples/vm/ to create a VM from the uploaded image.
#
# Prerequisites:
#   - A kubeconfig file with access to your Harvester cluster
#   - curl must be available on the machine running terraform apply
# -----------------------------------------------------------------------------

module "image" {
  source = "../../image"

  kubeconfig_path    = "/path/to/harvester-kubeconfig.yaml"
  image_source       = "upload"
  image_name         = "my-local-image"
  image_namespace    = "harvester-public"
  image_display_name = "My Locally Built Image"
  local_image_path   = "/path/to/my-image.qcow2"
}

output "image_id"        { value = module.image.image_id }
output "image_name"      { value = module.image.image_name }
output "image_namespace" { value = module.image.image_namespace }
output "image_state"     { value = module.image.image_state }
