variable "region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "The name of the S3 bucket to be used as the origin."
  type        = string
}

variable "sm_secret_name" {
  description = "The name of the secret that contains the private key."
  type        = string
}

variable "cf_key_id" {
  description = "The id of the cloudfront key."
  type        = string
}

variable "cf_key_group_name" {
  description = "The name of the cloudfront key group."
  type        = string
  default     = "url_signers"
}
