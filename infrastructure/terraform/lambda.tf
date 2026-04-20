data "archive_file" "lambda_dispatcher" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/dispatcher"
  output_path = "/tmp/invoiceshelf-dispatcher.zip"
}

resource "aws_cloudwatch_log_group" "lambda_dispatcher" {
  name              = "/aws/lambda/${var.project_name}-trello-dispatcher"
  retention_in_days = 14
}

resource "aws_lambda_function" "dispatcher" {
  function_name = "${var.project_name}-trello-dispatcher"
  description   = "Receives Trello webhooks and launches EC2 harness instances"

  s3_bucket        = aws_s3_bucket.lambda_packages.id
  s3_key           = aws_s3_object.lambda_dispatcher.key
  source_code_hash = data.archive_file.lambda_dispatcher.output_base64sha256

  handler = "handler.lambda_handler"
  runtime = "python3.12"
  timeout = 30

  role = aws_iam_role.lambda_execution.arn

  depends_on = [aws_cloudwatch_log_group.lambda_dispatcher]

  environment {
    variables = {
      PROJECT_NAME            = var.project_name
      TRELLO_BOARD_ID         = var.trello_board_id
      TRELLO_READY_LIST_NAME  = var.trello_ready_list_name
      GITHUB_REPO             = var.github_repo
      EC2_LAUNCH_TEMPLATE_ID  = aws_launch_template.harness.id
      EC2_SUBNET_ID           = data.aws_subnets.default.ids[0]
      ARTIFACTS_BUCKET        = aws_s3_bucket.artifacts.id
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "defaultForAz"
    values = ["true"]
  }
}
