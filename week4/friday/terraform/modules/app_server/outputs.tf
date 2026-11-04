output "vm_name" {
  description = "Name of the VM this module instance manages"
  value       = var.vm_name
}

output "vm_ip" {
  description = "Dynamically resolved IPv4 address of the VM"
  value       = data.external.vm_info.result.ip
}

output "ssh_command" {
  description = "SSH command to connect to this VM from the host"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${data.external.vm_info.result.ip}"
}
