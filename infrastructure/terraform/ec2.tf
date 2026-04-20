data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  # Use Packer-built AMI when provided, fall back to plain AL2023 for bootstrapping
  ami_id = var.harness_ami_id != "" ? var.harness_ami_id : data.aws_ami.amazon_linux_2023.id
}

resource "aws_launch_template" "harness" {
  name        = "${var.project_name}-harness"
  description = "Claude Code engineering harness runner"

  image_id      = local.ami_id
  instance_type = var.ec2_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.harness_ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.harness_ec2.id]
    delete_on_termination       = true
  }

  # shutdown -h now in the harness script terminates the instance
  instance_initiated_shutdown_behavior = "terminate"

  # IMDSv2 required
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-harness-runner"
      Project = "InvoiceShelf"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Project = "InvoiceShelf"
    }
  }
}
