# ── Lambda execution role ────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_harness" {
  name = "${var.project_name}-lambda-harness"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Management"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:DescribeInstances",
          "ec2:CreateTags",
          "ec2:DescribeTags",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeSubnets",
        ]
        Resource = "*"
      },
      {
        # Required so Lambda can assign the EC2 instance profile at launch
        Sid      = "PassEC2Role"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.harness_ec2.arn
      },
      {
        Sid    = "SSMJobManagement"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter",
          "ssm:SendCommand",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMReadSecrets"
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*"
      },
    ]
  })
}

# ── EC2 instance role ────────────────────────────────────────────────────────

resource "aws_iam_role" "harness_ec2" {
  name = "${var.project_name}-harness-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "harness_ec2" {
  name = "${var.project_name}-harness-ec2"
  role = aws_iam_role.harness_ec2.name
}

# Enables SSM Run Command for the iteration loop
resource "aws_iam_role_policy_attachment" "harness_ec2_ssm_core" {
  role       = aws_iam_role.harness_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "harness_ec2" {
  name = "${var.project_name}-harness-ec2"
  role = aws_iam_role.harness_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*"
      },
      {
        Sid    = "CleanupJobParam"
        Effect = "Allow"
        Action = ["ssm:DeleteParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/jobs/*"
      },
      {
        Sid    = "Artifacts"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
    ]
  })
}
