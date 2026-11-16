terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Recommended for CI/CD so state survives between runs. Create the bucket
  # once (manually), then uncomment and run `terraform init -migrate-state`.
  # backend "s3" {
  #   bucket = "YOUR-TFSTATE-BUCKET"
  #   key    = "serverless-pipeline/terraform.tfstate"
  #   region = "us-east-1"
  # }
}


  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

