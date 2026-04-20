terraform {
  backend "s3" {
    bucket         = "drp-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "drp-tfstate-lock"
    encrypt        = true
    profile        = "drp-mgmt"
  }
}
