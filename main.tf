resource "aws_s3_bucket" "origin_bucket" {
  bucket = var.bucket_name
}

data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.origin_bucket.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "origin_bucket_policy" {
  bucket = aws_s3_bucket.origin_bucket.id
  policy = data.aws_iam_policy_document.origin_bucket_policy.json
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "default-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name              = aws_s3_bucket.origin_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = "S3-origin"
  }
  enabled         = true
  is_ipv6_enabled = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    cache_policy_id  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-origin"

    viewer_protocol_policy = "redirect-to-https"

  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_100"
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy" "lambda_basic_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution.arn
}

data "aws_secretsmanager_secret" "signurl" {
  name = var.sm_secret_name
}

resource "aws_iam_policy" "lambda_secret_policy" {
  name = "lambda-read-signurl-secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = data.aws_secretsmanager_secret.signurl.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secret_readonly_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_secret_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/sign.py"
  output_path = "${path.module}/lambda/sign_function_payload.zip"
}

resource "aws_lambda_layer_version" "rsa_layer" {
  layer_name               = "rsa_layer"
  filename                 = "layer.zip"
  source_code_hash         = filebase64sha256("layer.zip")
  compatible_architectures = ["x86_64"]
  compatible_runtimes      = ["python3.13"]
}

resource "aws_lambda_function" "sign_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "sign_function"
  layers           = [aws_lambda_layer_version.rsa_layer.arn]
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "sign.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.13"

  environment {
    variables = {
      CF_KEY_ID      = var.cf_key_id
      CF_URL         = aws_cloudfront_distribution.cdn.domain_name
      SM_SECRET_NAME = var.sm_secret_name
    }
  }
}
