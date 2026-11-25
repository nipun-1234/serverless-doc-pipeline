variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "doc-pipeline"
}

variable "allowed_origins" {
  description = "Origins allowed by CORS (S3 + API). Use your site URL in production."
  type        = list(string)
  default     = ["*"]
}
