# ==============================================================================
# variables.tf — optional Google sign-in OAuth credentials
#
# Supplied by apply.sh from the GOOGLE_OAUTH_CLIENT_ID / _SECRET env vars so no
# secrets land in git. Leave them empty to ship email/password sign-in only —
# the Google provider in identity.tf is count-gated on both being non-empty.
# ==============================================================================

variable "google_oauth_client_id" {
  description = "OAuth 2.0 Web client ID for Google sign-in (empty = disabled)."
  type        = string
  default     = ""
}

variable "google_oauth_client_secret" {
  description = "OAuth 2.0 Web client secret for Google sign-in (empty = disabled)."
  type        = string
  default     = ""
  sensitive   = true
}
