packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

source "amazon-ebs" "harness" {
  region        = var.aws_region
  instance_type = var.instance_type

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ami_name        = "invoiceshelf-harness-{{timestamp}}"
  ami_description = "InvoiceShelf Claude Code engineering harness"
  ssh_username    = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name      = "InvoiceShelf Harness"
    Project   = "InvoiceShelf"
    ManagedBy = "Packer"
    BuildDate = "{{timestamp}}"
  }
}

build {
  name    = "invoiceshelf-harness"
  sources = ["source.amazon-ebs.harness"]

  provisioner "file" {
    source      = "scripts/harness.sh"
    destination = "/tmp/harness.sh"
  }

  provisioner "shell" {
    script = "scripts/install.sh"
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/harness",
      "sudo mv /tmp/harness.sh /opt/harness/run.sh",
      "sudo chmod +x /opt/harness/run.sh",
      # Smoke-test that key tools are present
      "node --version",
      "claude --version",
      "gh --version",
      "git --version",
      "php --version",
      "composer --version",
    ]
  }
}
