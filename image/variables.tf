variable "kubeconfig_path" {
  type        = string
  description = "Path to the Harvester kubeconfig file."
}

variable "image_name" {
  type        = string
  description = "Name for the VirtualMachineImage Kubernetes resource."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.image_name))
    error_message = "image_name must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "image_namespace" {
  type        = string
  description = "Namespace for the VirtualMachineImage resource."
  default     = "harvester-public"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.image_namespace))
    error_message = "image_namespace must be a valid Kubernetes name: lowercase alphanumeric and hyphens, no leading/trailing hyphen."
  }
}

variable "image_display_name" {
  type        = string
  description = "Human-readable display name for the image."
}

variable "image_source" {
  type        = string
  description = "Image ingestion mode: 'upload' (stream a local file) or 'download' (pull from URL)."

  validation {
    condition     = contains(["upload", "download"], var.image_source)
    error_message = "image_source must be 'upload' or 'download'. To reference an existing image use the vm/ module directly."
  }
}

variable "local_image_path" {
  type        = string
  description = "Absolute path to the local ISO/raw/qcow2 image file. Required when image_source is 'upload'."
  default     = ""

  validation {
    condition     = var.local_image_path == "" || can(regex("^/.+", var.local_image_path))
    error_message = "local_image_path must be an absolute path (starting with /) or left empty."
  }

  validation {
    condition     = var.local_image_path == "" || can(regex("(?i)\\.(iso|raw|qcow2|img)$", var.local_image_path))
    error_message = "local_image_path must end with a supported extension: .iso, .raw, .qcow2, or .img."
  }
}

variable "image_url" {
  type        = string
  description = "HTTP/HTTPS URL of the image to download. Required when image_source is 'download'."
  default     = ""

  validation {
    condition     = var.image_url == "" || can(regex("^https?://", var.image_url))
    error_message = "image_url must be a valid HTTP or HTTPS URL, or left empty."
  }
}

variable "storage_class_name" {
  type        = string
  description = "Storage class to use for the image. If not set, uses the cluster default."
  default     = ""
}
