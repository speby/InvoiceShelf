data "archive_file" "lambda_dispatcher" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/dispatcher"
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
      ARTIFACTS_BUCKET        = aws_s3_bucket.artifacts.id
    }
  }
}

resource "aws_vpc" "harness" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-harness" }
}

resource "aws_internet_gateway" "harness" {
  vpc_id = aws_vpc.harness.id
  tags   = { Name = "${var.project_name}-harness" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "harness_public" {
  vpc_id                  = aws_vpc.harness.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-harness-public" }
}

resource "aws_route_table" "harness_public" {
  vpc_id = aws_vpc.harness.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.harness.id
  }
  tags = { Name = "${var.project_name}-harness-public" }
}

resource "aws_route_table_association" "harness_public" {
  subnet_id      = aws_subnet.harness_public.id
  route_table_id = aws_route_table.harness_public.id
}
