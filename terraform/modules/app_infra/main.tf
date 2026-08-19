terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

# The VPC, subnets, internet/egress gateways, and route tables were removed in
# the client-side migration (Phase 3, Stage 5). The backend pipeline that lived
# in the VPC (ALB, ECS, ElastiCache) was decommissioned in Stages 1-3; the
# frontend (S3 + CloudFront, see frontend.tf) needs no VPC, so the now-empty
# network was torn down. Google is reached directly from the browser.
