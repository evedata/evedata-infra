terraform {
  required_providers {
    tailscale = {
      source = "tailscale/tailscale"
      version = "~> 0.16"
    }
  }
}

provider "tailscale" {
  scopes = ["all"]
}
