output "api_server_ip" {
  description = "IPv4 address of the KijaniKiosk API server (read dynamically from Multipass)"
  value       = data.external.vm_info.result.ip
}

output "api_server_hostname" {
  description = "Internal hostname of the API server"
  value       = "kijanikiosk-api"
}

output "ssh_command" {
  description = "SSH command to connect to the API server from the host"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${data.external.vm_info.result.ip}"
}

output "environment" {
  description = "Deployment environment for this server"
  value       = var.environment
}

output "connection_summary" {
  description = "Human-readable summary of the connection"
  value       = "Server 'kijanikiosk-api' in environment '${var.environment}' is at ${data.external.vm_info.result.ip}"
}
