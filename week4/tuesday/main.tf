terraform {
  required_version = ">= 1.6.0"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# --- Data source: read the Multipass VM IP dynamically ---
# This is the "no hardcoded IPs" requirement. If the VM is recreated
# with a different IP, the next terraform plan picks up the new value.
data "external" "vm_info" {
  program = ["bash", "-c", <<-EOT
    multipass info kijanikiosk-api --format json | \
    jq -c '{"ip": .info["kijanikiosk-api"].ipv4[0]}'
  EOT
  ]
}

# --- Null resource: connect to the VM and run a trivial command ---
# The null_resource does not manage the VM itself (Multipass does).
# It manages the "connection and configuration" step.
resource "null_resource" "kijanikiosk_api" {
  triggers = {
    vm_ip       = data.external.vm_info.result.ip
    environment = var.environment
  }

  connection {
    type        = "ssh"
    host        = data.external.vm_info.result.ip
    user        = "ubuntu"
    private_key = file("/home/medico/.ssh/id_rsa")
    agent       = false
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Connected to kijanikiosk-api (${var.environment})'",
      "uname -a",
      "lsb_release -a",
    ]
  }
}
