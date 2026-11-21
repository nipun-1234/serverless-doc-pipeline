variable "aws_region" {
  type    = string
  default = "us-east-1"
}



variable "allowed_origins" {
  description = "Origins allowed by CORS (S3 + API). Use your site URL in production."
  type        = list(string)
  default     = ["*"]
}
