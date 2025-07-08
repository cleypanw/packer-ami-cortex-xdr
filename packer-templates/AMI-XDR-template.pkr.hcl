packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region where the AMI will be built"
}

variable "xdr_url" {
  type        = string
  description = "Cortex API URL"
}

variable "distribution_id" {
  type        = string
  description = "Cortex Agent installer distribution ID"
}

variable "auth_id" {
  type        = string
  description = "Cortex Auth ID"
  sensitive   = true
}

variable "auth_token" {
  type        = string
  description = "Cortex Auth Token"
  sensitive   = true
}

variable "xdr_tags" {
  type        = string
  description = "Tags applied on XDR agent"
}

source "amazon-ebs" "xdr-agent" {
  region       = var.aws_region
  source_ami   = "ami-0388f26d76e0472c6" # Ubuntu 22.04 LTS - eu-west-3
  instance_type = "t2.micro"
  ssh_username = "ubuntu"
  ami_name     = "xdr-agent-ubuntu-{{timestamp}}"

  tags = {
    Name    = "XDR Agent Ubuntu AMI"
    OS      = "Ubuntu"
    BuiltBy = "Packer"
  }
}

build {
  sources = ["source.amazon-ebs.xdr-agent"]

  provisioner "file" {
    source      = "../scripts/install-xdr-linux-auto.sh" # <- ajuste si le script est ailleurs
    destination = "/tmp/install-xdr.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install-xdr.sh",
      "bash -x /tmp/install-xdr.sh '${var.xdr_url}' '${var.distribution_id}' '${var.auth_id}' '${var.auth_token}' '${var.xdr_tags}'"
    ]
  }
}
