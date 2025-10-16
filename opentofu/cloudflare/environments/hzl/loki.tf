resource "cloudflare_r2_bucket" "hzl-loki-admin-weu" {
  account_id = var.cloudflare_account_id
  name       = "hzl-loki-admin-weu"
  location   = "WEUR"
}

resource "cloudflare_r2_bucket" "hzl-loki-chunk-weu" {
  account_id = var.cloudflare_account_id
  name       = "hzl-loki-chunk-weu"
  location   = "WEUR"
}

resource "cloudflare_r2_bucket" "hzl-loki-ruler-weu" {
  account_id = var.cloudflare_account_id
  name       = "hzl-loki-ruler-weu"
  location   = "WEUR"
}
