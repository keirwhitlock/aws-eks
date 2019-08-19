terraform {
  backend "s3" {
    bucket         = "terraform-state-dev"
    key            = "eks-core-cluster/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-management"
    profile        = "dev"
  }
}

locals {
  region  = "eu-west-1"
  profile = "dev"
}

provider "aws" {
  profile = local.profile
  region  = local.region
}

data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket  = "terraform-state-dev"
    key     = "dev/terraform.tfstate"
    profile = local.profile
    region  = local.region
    encrypt = "true"
  }
}

