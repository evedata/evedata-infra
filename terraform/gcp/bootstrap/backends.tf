terraform {
  backend "gcs" {
    bucket = "evedata-terraform"
    prefix = "gcp/bootstrap"
  }
}
