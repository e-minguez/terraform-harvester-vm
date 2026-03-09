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
# Example: create a VM from an image already present in Harvester.
#
# The image/ module is NOT needed here — the vm/ module looks up the image
# by name via a data source and does not manage its lifecycle.
#
# To find the Kubernetes resource name of an existing image:
#   kubectl --kubeconfig=<path> get virtualmachineimages.harvesterhci.io -A
# -----------------------------------------------------------------------------

module "vm" {
  source = "../../vm"

  kubeconfig_path   = "/path/to/harvester-kubeconfig.yaml"
  vm_name           = "my-vm"
  vm_namespace      = "default"
  image_name        = "image-74wx4"            # kubectl name (not display name)
  image_namespace   = "harvester-public"
  network_name      = "vlan10"
  network_namespace = "default"
  cpu               = 2
  memory            = "4Gi"
  disk_size         = "40Gi"

  # Optional: create multiple VMs from the same image.
  # Names will be my-vm-0, my-vm-1, my-vm-2.
  # vm_count = 3

  # Optional: assign specific MAC addresses (positional; missing entries auto-assign).
  # mac_addresses = ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"]

  # Optional: use legacy BIOS instead of UEFI (default).
  # efi = false
}

output "vm_names" { value = module.vm.vm_names }
output "vm_ids"   { value = module.vm.vm_ids }
output "image_id" { value = module.vm.image_id }
