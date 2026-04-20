output "webhook_url" {
  description = "Trello webhook callback URL — register this with the register_webhook.sh script"
  value       = "${aws_apigatewayv2_api.webhook.api_endpoint}/webhook/trello"
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.webhook.id
}

output "lambda_function_name" {
  description = "Dispatcher Lambda function name"
  value       = aws_lambda_function.dispatcher.function_name
}

output "lambda_log_group" {
  description = "CloudWatch log group for the dispatcher Lambda"
  value       = aws_cloudwatch_log_group.lambda_dispatcher.name
}

output "artifacts_bucket" {
  description = "S3 bucket for job artifacts and logs"
  value       = aws_s3_bucket.artifacts.id
}

output "launch_template_id" {
  description = "EC2 Launch Template ID for harness runners"
  value       = aws_launch_template.harness.id
}

output "harness_ec2_role_arn" {
  description = "IAM role ARN attached to harness EC2 instances"
  value       = aws_iam_role.harness_ec2.arn
}
