terraform {
  required_version = ">= 1.4"

  required_providers {
    harvester = {
      source  = "registry.terraform.io/harvester/harvester"
      version = ">= 0.6.4"
    }
  }
}
