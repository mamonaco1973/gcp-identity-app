# Identity Platform is enabled and configured via api_setup.sh (REST API).
# It cannot be disabled once active, so it is intentionally not managed here.

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

}

output "firebase_api_key" {
  value     = google_apikeys_key.webapp.key_string
  sensitive = true
}
