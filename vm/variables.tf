variable "kubeconfig_path" {
  type        = string
  description = "Path to the Harvester kubeconfig file."
}

variable "vm_name" {
  type        = string
  description = "Name of the virtual machine resource."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.vm_name))
    error_message = "vm_name must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "vm_namespace" {
  type        = string
  description = "Kubernetes namespace where the VM will be created."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.vm_namespace))
    error_message = "vm_namespace must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "image_name" {
  type        = string
  description = "Kubernetes resource name of the existing VirtualMachineImage to boot from."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.image_name))
    error_message = "image_name must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "image_namespace" {
  type        = string
  description = "Namespace of the VirtualMachineImage resource."
  default     = "harvester-public"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.image_namespace))
    error_message = "image_namespace must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "network_name" {
  type        = string
  description = "Name of the existing Harvester network (VLAN) to attach to the VM."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.network_name))
    error_message = "network_name must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "network_namespace" {
  type        = string
  description = "Namespace of the existing Harvester network."
  default     = "default"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.network_namespace))
    error_message = "network_namespace must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "cpu" {
  type        = number
  description = "Number of virtual CPUs for the VM."
  default     = 2

  validation {
    condition     = var.cpu >= 1
    error_message = "cpu must be at least 1."
  }
}

variable "memory" {
  type        = string
  description = "Memory allocation for the VM (e.g. '4Gi', '8Gi')."
  default     = "4Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory))
    error_message = "memory must be a value like '2Gi', '4096Mi', etc."
  }
}

variable "disk_size" {
  type        = string
  description = "Root disk size (e.g. '40Gi', '100Gi')."
  default     = "40Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.disk_size))
    error_message = "disk_size must be a value like '40Gi', '100Gi', etc."
  }
}

variable "vm_count" {
  type        = number
  description = "Number of VMs to create. Names are suffixed with the index when greater than 1 (e.g. 'my-vm-0', 'my-vm-1')."
  default     = 1

  validation {
    condition     = var.vm_count >= 1
    error_message = "vm_count must be at least 1."
  }
}

variable "mac_addresses" {
  type        = list(string)
  description = "Optional list of MAC addresses, one per VM (positional). Shorter lists leave remaining VMs with auto-assigned MACs."
  default     = []

  validation {
    condition     = alltrue([for m in var.mac_addresses : can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", m))])
    error_message = "Each entry in mac_addresses must be a valid MAC address (e.g. 'AA:BB:CC:DD:EE:FF')."
  }
}

variable "efi" {
  type        = bool
  description = "Boot the VM with UEFI firmware. Set to false for legacy BIOS."
  default     = true
}

variable "storage_class_name" {
  type        = string
  description = "Storage class to use for the root disk. If not set, uses the cluster default."
  default     = ""
}
