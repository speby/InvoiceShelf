resource "aws_ssm_parameter" "trello_api_key" {
  name        = "/${var.project_name}/trello/api_key"
  type        = "SecureString"
  value       = var.trello_api_key
  description = "Trello API key (public identifier)"
}

resource "aws_ssm_parameter" "trello_api_secret" {
  name        = "/${var.project_name}/trello/api_secret"
  type        = "SecureString"
  value       = var.trello_api_secret
  description = "Trello API secret (used for webhook HMAC-SHA1 signature validation)"
}

resource "aws_ssm_parameter" "trello_api_token" {
  name        = "/${var.project_name}/trello/api_token"
  type        = "SecureString"
  value       = var.trello_api_token
  description = "Trello OAuth token (for API calls)"
}

resource "aws_ssm_parameter" "github_pat" {
  name        = "/${var.project_name}/github/pat"
  type        = "SecureString"
  value       = var.github_pat
  description = "GitHub Personal Access Token"
}

resource "aws_ssm_parameter" "claude_api_key" {
  name        = "/${var.project_name}/claude/api_key"
  type        = "SecureString"
  value       = var.claude_api_key
  description = "Anthropic Claude API key"
}
