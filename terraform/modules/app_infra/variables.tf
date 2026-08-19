variable "app_name" {
  description = "Application name prefix for resource naming (e.g. drp)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

# Not marked sensitive: this is the address users type. It is on the OAuth
# consent screen, in Search Console and in the privacy policy, so secrecy would
# be a fiction — and it would redact every plan diff that touches ACM or
# CloudFront, including the DNS records the certificate needs published.
variable "frontend_domain_name" {
  description = "Custom domain for the CloudFront frontend distribution"
  type        = string

  # An unset GitHub variable arrives as TF_VAR_frontend_domain_name="", which
  # Terraform accepts as a real value rather than a missing one. That would
  # replace the ACM certificate and strip the CloudFront alias, so refuse it
  # here instead.
  validation {
    condition     = length(var.frontend_domain_name) > 0
    error_message = "frontend_domain_name must not be empty."
  }
}
