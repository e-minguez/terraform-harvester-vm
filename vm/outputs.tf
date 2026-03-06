output "vm_names" {
  description = "Names of the created virtual machines."
  value       = harvester_virtualmachine.vm[*].name
}

output "vm_ids" {
  description = "Resource IDs of the created virtual machines."
  value       = harvester_virtualmachine.vm[*].id
}

output "image_id" {
  description = "Resource ID of the image used for the VMs."
  value       = data.harvester_image.image.id
}
