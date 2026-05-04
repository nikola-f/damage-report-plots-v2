terraform {
  backend "s3" {
    bucket         = "drp-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    use_lockfile   = true
    encrypt        = true
  }
}
