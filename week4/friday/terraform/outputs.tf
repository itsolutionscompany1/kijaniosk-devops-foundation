output "api_server_ip" {
  description = "IPv4 address of the KijaniKiosk API server"
  value       = module.app_servers["api"].vm_ip
}

output "payments_server_ip" {
  description = "IPv4 address of the KijaniKiosk payments server"
  value       = module.app_servers["payments"].vm_ip
}

output "logs_server_ip" {
  description = "IPv4 address of the KijaniKiosk logs server"
  value       = module.app_servers["logs"].vm_ip
}

output "all_server_ips" {
  description = "Map of server role -> IP address, for feeding Ansible inventory"
  value = {
    for key, mod in module.app_servers : key => mod.vm_ip
  }
}

output "ssh_commands" {
  description = "Map of server role -> SSH command"
  value = {
    for key, mod in module.app_servers : key => mod.ssh_command
  }
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}
