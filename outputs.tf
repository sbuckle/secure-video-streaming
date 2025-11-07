output "cloudfront_domain_name" {
  description = "The URL of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.sign_api.api_endpoint
}
