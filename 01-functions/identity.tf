# Identity Platform is INITIALIZED and its email/password sign-in is turned on by
# api_setup.sh (REST) — that part stays out of Terraform because the config
# singleton can't be disabled once active. What Terraform manages here (mirroring
# gcp-resume-app) is the authorized domains and the optional Google sign-in
# provider, which are safe to declare and tear down.

# ─── Browser API Key ─────────────────────────────────────────────────────────
# Scoped to Identity Platform only — safe to embed in the SPA.

resource "random_id" "apikey_suffix" {
  byte_length = 3
}

resource "google_apikeys_key" "webapp" {
  name         = "notes-webapp-key-${random_id.apikey_suffix.hex}"
  display_name = "Notes Web App API Key"
  project      = local.credentials.project_id

  restrictions {
    api_targets {
      service = "identitytoolkit.googleapis.com"
    }
  }

}

output "firebase_api_key" {
  value     = google_apikeys_key.webapp.key_string
  sensitive = true
}

# ─── Identity Platform authorized domains ─────────────────────────────────────
# Add storage.googleapis.com so the GCS-hosted SPA can open Google sign-in popups
# without an unauthorized-domain error. The default domains are listed explicitly
# because Terraform replaces the whole list when it manages this resource.

resource "google_identity_platform_config" "default" {
  provider = google-beta

  authorized_domains = [
    "localhost",
    "${local.credentials.project_id}.firebaseapp.com",
    "${local.credentials.project_id}.web.app",
    "storage.googleapis.com",
  ]
}

# ─── Google sign-in provider ──────────────────────────────────────────────────
# Only provisioned when both OAuth credentials are supplied (env-driven via
# apply.sh). Empty creds => email/password only, no Google button backing.

resource "google_identity_platform_default_supported_idp_config" "google_sign_in" {
  count    = (var.google_oauth_client_id != "" && var.google_oauth_client_secret != "") ? 1 : 0
  provider = google-beta

  enabled       = true
  idp_id        = "google.com"
  client_id     = var.google_oauth_client_id
  client_secret = var.google_oauth_client_secret
}
