resource "aws_cloudtrail" "main" {
  name                          = "drp-dev"
  s3_bucket_name                = "drp-cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}
