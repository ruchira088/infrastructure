provider "aws" {
  region = "ap-southeast-2"
}

provider "random" {
}

terraform {
  backend "s3" {
    bucket = "terraform.ruchij.com"
    key = "k3s-cluster.tfstate"
    region = "ap-southeast-2"
  }

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}