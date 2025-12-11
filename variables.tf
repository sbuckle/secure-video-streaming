variable "region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "The name of the S3 bucket to be used as the origin."
  type        = string
}

variable "secret_name" {
  description = "The name of the secret that contains the private key for signing CloudFront URLs."
  type        = string
  default     = "signing_key"
}

variable "cf_key_group_name" {
  description = "The name of the cloudfront key group."
  type        = string
  default     = "url_signers"
}

variable "public_key_file" {
  description = "The name of the file that contains the public key."
  type        = string
  default     = "public_key.pem"
}

variable "private_key_file" {
  description = "The name of the file that contains the private key."
  type        = string
  default     = "private_key.pem"
}
