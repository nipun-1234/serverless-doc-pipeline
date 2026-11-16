data "aws_caller_identity" "current" {}

locals {
  name          = var.project_name
  account_id    = data.aws_caller_identity.current.account_id
  processor_zip = "${path.module}/../backend/build/processor.zip"
  api_zip       = "${path.module}/../backend/build/api.zip"
}

############################
# Storage
############################
resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name}-uploads-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket" "processed" {
  bucket        = "${local.name}-processed-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = var.allowed_origins
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# Keep costs low: delete raw uploads after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    id     = "expire-old-uploads"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

############################
# Database
############################
resource "aws_dynamodb_table" "files" {
  name         = "${local.name}-files"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

############################
# IAM - processor
############################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "processor" {
  name               = "${local.name}-processor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "processor" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.processed.arn}/*"]
  }
  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
}

resource "aws_iam_role_policy" "processor" {
  name   = "least-privilege"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.processor.json
}

resource "aws_iam_role_policy_attachment" "processor_logs" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################
# IAM - api
############################
resource "aws_iam_role" "api" {
  name               = "${local.name}-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "api" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.processed.arn}/*"]
  }
  statement {
    actions   = ["dynamodb:Scan"]
    resources = [aws_dynamodb_table.files.arn]
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "least-privilege"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

resource "aws_iam_role_policy_attachment" "api_logs" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################
# Lambda functions
############################
resource "aws_lambda_function" "processor" {
  function_name    = "${local.name}-processor"
  role             = aws_iam_role.processor.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = local.processor_zip
  source_code_hash = filebase64sha256(local.processor_zip)
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.files.name
      PROCESSED_BUCKET = aws_s3_bucket.processed.id
    }
  }
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.name}-api"
  role             = aws_iam_role.api.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = local.api_zip
  source_code_hash = filebase64sha256(local.api_zip)
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.files.name
      UPLOAD_BUCKET    = aws_s3_bucket.uploads.id
      PROCESSED_BUCKET = aws_s3_bucket.processed.id
    }
  }
}

############################
# S3 -> Lambda trigger
############################
resource "aws_lambda_permission" "allow_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.processor.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.uploads.arn
  source_account = local.account_id
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

############################
# API Gateway (HTTP API)
############################
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_url" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "list_files" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /files"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
