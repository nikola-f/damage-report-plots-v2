terraform {
  backend "s3" {
    bucket         = "drp-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "drp-tfstate-lock"
    encrypt        = true
  }
}
