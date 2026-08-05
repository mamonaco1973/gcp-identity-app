# Identity Platform init, email/password sign-in, AND the authorized domains are
# all handled by api_setup.sh (REST): the config is a singleton Terraform can't
# create-manage once Identity Platform is initialized (400 "already enabled").
# Terraform manages only the optional Google sign-in PROVIDER below — a distinct
# sub-resource that creates and destroys cleanly.

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
