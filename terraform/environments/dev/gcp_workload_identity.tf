resource "google_project_service" "gmail" {
  service            = "gmail.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sheets" {
  service            = "sheets.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts" {
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials" {
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.iam]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.actor"       = "assertion.actor"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
    "attribute.ref"         = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}' && assertion.environment == 'dev' && (assertion.ref == 'refs/heads/develop' || assertion.ref.startsWith('refs/pull/'))"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "terraform_cicd" {
  account_id   = "terraform-cicd"
  display_name = "Terraform CI/CD"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.terraform_cicd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

locals {
  terraform_cicd_roles = toset([
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
  ])
}

resource "google_project_iam_member" "terraform_cicd" {
  for_each = local.terraform_cicd_roles

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_cicd.email}"
}
