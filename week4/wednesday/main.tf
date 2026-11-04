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

  backend "s3" {
    bucket                      = "kijanikiosk-tfstate"
    key                         = "staging/terraform.tfstate"
    region                      = "us-east-1"
    endpoints = {
      s3 = "http://localhost:9000"
    }
    access_key                  = "minioadmin"
    secret_key                  = "minioadmin"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    use_path_style              = true
  }
}

locals {
  servers = {
    api      = { vm_name = "kijanikiosk-api" }
    payments = { vm_name = "kijanikiosk-payments" }
    logs     = { vm_name = "kijanikiosk-logs" }
  }
}

module "app_servers" {
  source   = "./modules/app_server"
  for_each = local.servers

  vm_name     = each.value.vm_name
  environment = var.environment
}
