output "cloudfront_domain_name" {
  description = "The URL of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.domain_name
}
