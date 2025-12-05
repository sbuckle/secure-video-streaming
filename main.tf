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

data "aws_cloudfront_response_headers_policy" "cors_policy" {
  name = "Managed-SimpleCORS"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name              = aws_s3_bucket.origin_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = "S3-origin"
  }

  origin {
    origin_id   = "signing-api-origin"
    domain_name = replace(aws_apigatewayv2_api.sign_api.api_endpoint, "https://", "")
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id   = "rewrite-api-origin"
    domain_name = replace(aws_apigatewayv2_api.rewrite_api.api_endpoint, "https://", "")
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  enabled         = true
  is_ipv6_enabled = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "signing-api-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  ordered_cache_behavior {
    path_pattern           = "*.m3u8"
    target_origin_id       = "rewrite-api-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.cors_policy.id
  }

  ordered_cache_behavior {
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    path_pattern               = "*.ts"
    target_origin_id           = "S3-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.cors_policy.id
    trusted_key_groups         = [aws_cloudfront_key_group.cf_key_group.id]
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_100"
}

resource "aws_cloudfront_key_group" "cf_key_group" {
  name  = var.cf_key_group_name
  items = [var.cf_key_id]
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
      CF_URL         = "https://${aws_cloudfront_distribution.cdn.domain_name}"
      SM_SECRET_NAME = var.sm_secret_name
    }
  }
}

resource "aws_apigatewayv2_api" "sign_api" {
  name          = "sign-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.sign_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sign_function.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.sign_api.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.sign_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sign_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sign_api.execution_arn}/*/*"
}

resource "aws_iam_role" "rewrite_execution_role" {
  name               = "rewrite_execution_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "rewrite_lambda_basic_execution_attach" {
  role       = aws_iam_role.rewrite_execution_role.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution.arn
}

resource "aws_iam_policy" "s3_bucket_policy" {
  name = "s3-bucket-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.origin_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rewrite_lambda_s3_policy_attach" {
  role       = aws_iam_role.rewrite_execution_role.name
  policy_arn = aws_iam_policy.s3_bucket_policy.arn
}

data "archive_file" "rewrite_function_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/rewrite.py"
  output_path = "${path.module}/lambda/rewrite_function_payload.zip"
}

resource "aws_lambda_function" "rewrite_function" {
  filename         = data.archive_file.rewrite_function_zip.output_path
  function_name    = "rewrite_function"
  role             = aws_iam_role.rewrite_execution_role.arn
  handler          = "rewrite.lambda_handler"
  source_code_hash = data.archive_file.rewrite_function_zip.output_base64sha256
  runtime          = "python3.13"

  environment {
    variables = {
      KEY_PREFIX = "-PREFIX"
      S3_BUCKET  = var.bucket_name
    }
  }
}

resource "aws_apigatewayv2_api" "rewrite_api" {
  name          = "rewrite-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "rewrite_lambda_integration" {
  api_id                 = aws_apigatewayv2_api.rewrite_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.rewrite_function.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "rewrite_get_route" {
  api_id    = aws_apigatewayv2_api.rewrite_api.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.rewrite_lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "rewrite_default_stage" {
  api_id      = aws_apigatewayv2_api.rewrite_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_rewrite_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rewrite_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rewrite_api.execution_arn}/*/*"
}
