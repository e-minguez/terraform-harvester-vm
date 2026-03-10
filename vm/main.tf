provider "harvester" {
  kubeconfig = var.kubeconfig_path
}

# ---------------------------------------------------------------------------
# Look up the image — it must already exist and be Active in Harvester.
# Manage images with the image/ module.
# ---------------------------------------------------------------------------

data "harvester_image" "image" {
  name      = var.image_name
  namespace = var.image_namespace
}

# ---------------------------------------------------------------------------
# Virtual Machine
# ---------------------------------------------------------------------------

resource "harvester_virtualmachine" "vm" {
  count                = var.vm_count
  name                 = var.vm_count == 1 ? var.vm_name : "${var.vm_name}-${count.index}"
  namespace            = var.vm_namespace
  restart_after_update = true

  cpu    = var.cpu
  memory = var.memory
  efi    = var.efi

  network_interface {
    name           = "default"
    network_name   = "${var.network_namespace}/${var.network_name}"
    type           = "bridge"
    wait_for_lease = true
    mac_address    = length(var.mac_addresses) > count.index ? var.mac_addresses[count.index] : null
  }

  disk {
    name               = "rootdisk"
    type               = "disk"
    size               = var.disk_size
    bus                = "virtio"
    boot_order         = 1
    image       = data.harvester_image.image.id
    auto_delete = true
  }

  lifecycle {
    precondition {
      condition     = length(var.mac_addresses) <= var.vm_count
      error_message = "mac_addresses has ${length(var.mac_addresses)} entries but vm_count is ${var.vm_count}. Provide at most one MAC per VM."
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "5m"
  }
}
