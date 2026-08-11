resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# ACM certificate for CloudFront (must be in us-east-1)
resource "aws_acm_certificate" "frontend" {
  provider          = aws.us_east_1
  domain_name       = var.frontend_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Content-Security-Policy for the SPA. This is the app's main defence in depth:
# the browser holds a gmail.readonly bearer token in JS memory for ~1h, so a
# single XSS would mean full mailbox read plus exfiltration — which would also
# void the Limited Use claim the OAuth verification rests on. React escaping and
# the absence of innerHTML are the only other barriers, and neither is a
# boundary.
#
# The Vite build emits no inline script (see apps/web/dist/index.html: one
# external module + one external stylesheet), so script-src needs no
# 'unsafe-inline' and no hashes. Sources, all of them load-bearing:
#   script-src  accounts.google.com/gsi/client — GIS, injected by sync/auth.ts
#   connect-src accounts.google.com (GIS status), www.googleapis.com (Drive,
#               userinfo, the Gmail batch endpoint), gmail/sheets.googleapis.com
#   img-src     *.googleusercontent.com — the signed-in user's profile picture
#   frame-src   accounts.google.com — GIS iframes
# 'unsafe-inline' survives only in style-src, for two style="margin: 0"
# attributes in public/*.html and whatever GIS injects.
#
# Enforced (it shipped Report-Only first): a sign-in → full sync → copy run on
# dev with the console open produced no violations, so the policy is now known
# to cover the app's real request set rather than only its readable one.
locals {
  frontend_csp = join("; ", [
    "default-src 'none'",
    "script-src 'self' https://accounts.google.com/gsi/client",
    join(" ", [
      "connect-src 'self'",
      "https://accounts.google.com",
      "https://www.googleapis.com",
      "https://gmail.googleapis.com",
      "https://sheets.googleapis.com",
    ]),
    "img-src 'self' data: https://*.googleusercontent.com",
    "style-src 'self' 'unsafe-inline'",
    "frame-src https://accounts.google.com",
    "base-uri 'none'",
    "object-src 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ])
}

resource "aws_cloudfront_response_headers_policy" "frontend_security" {
  name = "${local.name_prefix}-frontend-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    content_security_policy {
      content_security_policy = local.frontend_csp
      override                = true
    }
  }

  custom_headers_config {
    # GIS delivers the access token through a popup it opens and then talks to
    # via postMessage, so the popup must keep its opener reference: this must be
    # same-origin-allow-popups, never same-origin, which would break sign-in.
    items {
      header   = "Cross-Origin-Opener-Policy"
      value    = "same-origin-allow-popups"
      override = true
    }

    # The app uses none of these; denying them costs nothing and shrinks what a
    # successful injection could reach for.
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
      override = true
    }
  }
}

# SPA routing scoped to the S3 behavior (see functions/spa_rewrite.js).
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${local.name_prefix}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless paths to /index.html for SPA routing"
  publish = true
  code    = file("${path.module}/functions/spa_rewrite.js")
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [var.frontend_domain_name]

  # Origin 1: S3 (static files)
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Default behavior: S3 (static files)
  default_cache_behavior {
    target_origin_id       = "S3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # CachingOptimized
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend_security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  # The Rails API/ALB origin and its /api/* and /auth/* behaviors were removed
  # in the client-side migration (Phase 3, Stage 1): the SPA now talks to Google
  # directly, so the frontend distribution serves only static files.

  # SPA routing is handled by the spa_rewrite viewer-request function on the
  # S3 behavior.

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.frontend.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}
