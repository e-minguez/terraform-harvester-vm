output "image_id" {
  description = "Resource ID of the managed image."
  value = var.image_source == "upload" ? (
    length(harvester_image.upload) > 0 ? harvester_image.upload[0].id : ""
  ) : (
    length(harvester_image.download) > 0 ? harvester_image.download[0].id : ""
  )
}

output "image_name" {
  description = "Kubernetes resource name of the image (pass to vm/ module as image_name)."
  value       = var.image_name
}

output "image_namespace" {
  description = "Namespace of the image (pass to vm/ module as image_namespace)."
  value       = var.image_namespace
}

output "image_state" {
  description = "Current state of the image (e.g. Active)."
  value = var.image_source == "upload" ? (
    length(harvester_image.upload) > 0 ? harvester_image.upload[0].state : ""
  ) : (
    length(harvester_image.download) > 0 ? harvester_image.download[0].state : ""
  )
}
