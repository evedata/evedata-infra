resource "cloudflare_dns_record" "evedata_io-txt-github-verification" {
  content  = "\"8766f5c698\""
  name     = "_gh-evedata-o"
  proxied  = false
  ttl      = 3600
  type     = "TXT"
  zone_id  = local.zone_map["evedata.io"].id
  settings = {}
}

resource "cloudflare_dns_record" "evedata_io-txt-google-site-verification" {
  content  = "\"google-site-verification=mOu9mjHGUYz_CV4-3yPZBseE6LiqIneFrfSa9bBioCs\""
  name     = "evedata.io"
  proxied  = false
  ttl      = 3600
  type     = "TXT"
  zone_id  = local.zone_map["evedata.io"].id
  settings = {}
}
