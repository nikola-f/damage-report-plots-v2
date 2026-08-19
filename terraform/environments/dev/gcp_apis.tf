# Google APIs enabled on this environment's GCP project. dev and prod are
# separate projects, so each enables its own copy — and this file is kept
# identical between the two on purpose: the drift that hid here (prod declared
# neither gmail nor sheets, and neither project declared drive) is exactly what
# a first prod sync would have failed on.

# Called by the browser with the end user's own token, so they must be enabled
# on the project that owns the OAuth client:
#   gmail  — threads.list / threads.get          (apps/web/src/sync/gmail.ts)
#   sheets — spreadsheets create / append / get  (sheets.ts)
#   drive  — drive/v3/files appProperties lookup that finds the user's own
#            spreadsheet across devices (drive.ts); required by the drive.file
#            scope that replaced the sensitive spreadsheets scope
resource "google_project_service" "gmail" {
  service            = "gmail.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sheets" {
  service            = "sheets.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "drive" {
  service            = "drive.googleapis.com"
  disable_on_destroy = false
}

# Needed by Terraform itself and by Workload Identity Federation.
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
