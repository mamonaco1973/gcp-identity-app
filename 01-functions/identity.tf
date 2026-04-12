# ─── Identity Platform ───────────────────────────────────────────────────────

resource "google_identity_platform_config" "default" {
  project = local.credentials.project_id

  sign_in {
    email {
      enabled           = true
      password_required = true
    }
  }
}

# ─── Browser API Key ─────────────────────────────────────────────────────────
# Scoped to Identity Platform only — safe to embed in the SPA.

resource "google_apikeys_key" "webapp" {
  name         = "notes-webapp-key"
  display_name = "Notes Web App API Key"
  project      = local.credentials.project_id

  restrictions {
    api_targets {
      service = "identitytoolkit.googleapis.com"
    }
  }

  depends_on = [google_identity_platform_config.default]
}

output "firebase_api_key" {
  value     = google_apikeys_key.webapp.key_string
  sensitive = true
}
