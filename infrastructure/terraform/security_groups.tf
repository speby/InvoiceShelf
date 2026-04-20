resource "aws_security_group" "harness_ec2" {
  name        = "${var.project_name}-harness-ec2"
  description = "Harness EC2 instances — outbound only; SSM and GitHub accessed over HTTPS"

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-harness-ec2"
  }
}
