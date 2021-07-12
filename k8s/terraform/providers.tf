provider "aws" {
  region = "ap-southeast-2"
}

terraform {
  backend "s3" {
    bucket = "terraform.ruchij.com"
    key = "k8s.tfstate"
    region = "ap-southeast-2"
  }
}