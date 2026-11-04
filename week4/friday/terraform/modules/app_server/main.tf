terraform {
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

data "external" "vm_info" {
  program = ["bash", "-c", <<-EOT
    multipass info ${var.vm_name} --format json | \
    jq -c '{"ip": .info["${var.vm_name}"].ipv4[0]}'
  EOT
  ]
}

resource "null_resource" "this" {
  triggers = {
    vm_name     = var.vm_name
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
      "echo 'Connected to ${var.vm_name} (${var.environment})'",
      "hostname",
      "uname -a",
    ]
  }
}
