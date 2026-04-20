variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "invoiceshelf"
}

variable "trello_api_key" {
  description = "Trello API key (short hex string from https://trello.com/app-key)"
  type        = string
  sensitive   = true
}

variable "trello_api_secret" {
  description = "Trello API secret (from https://trello.com/app-key, used for webhook HMAC validation)"
  type        = string
  sensitive   = true
}

variable "trello_api_token" {
  description = "Trello OAuth token (for API calls)"
  type        = string
  sensitive   = true
}

variable "trello_board_id" {
  description = "Trello board ID"
  type        = string
  default     = "jFWLnGp4"
}

variable "trello_ready_list_name" {
  description = "Exact name of the Trello list that triggers the harness"
  type        = string
  default     = "Ready for Claude Code"
}

variable "github_pat" {
  description = "GitHub Personal Access Token with repo and pull_request permissions"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format"
  type        = string
  default     = "speby/InvoiceShelf"
}

variable "claude_api_key" {
  description = "Anthropic Claude API key"
  type        = string
  sensitive   = true
}

variable "harness_ami_id" {
  description = "AMI ID built by Packer. Leave empty to fall back to base Amazon Linux 2023 with bootstrap."
  type        = string
  default     = ""
}

variable "ec2_instance_type" {
  description = "EC2 instance type for harness runners"
  type        = string
  default     = "t3.large"
}
