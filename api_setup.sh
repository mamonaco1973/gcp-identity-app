#!/usr/bin/env bash
set -euo pipefail

if [ ! -f credentials.json ]; then
  echo "ERROR: credentials.json not found in repo root."
  exit 1
fi

project_id=$(jq -r '.project_id' credentials.json)
client_email=$(jq -r '.client_email' credentials.json)

echo "NOTE: Authenticating with GCP project: ${project_id}"
gcloud auth activate-service-account "${client_email}" --key-file=credentials.json
gcloud config set project "${project_id}"

echo "NOTE: Enabling required GCP APIs..."
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  firestore.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  artifactregistry.googleapis.com \
  identitytoolkit.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  apikeys.googleapis.com

access_token=$(gcloud auth print-access-token)

# The Identity Platform config is a singleton that must be PROVISIONED before it
# can be updated — UpdateConfig (the PATCH below) returns 404
# CONFIGURATION_NOT_FOUND on a project where Identity Platform was never turned
# on. initializeAuth creates it; it is idempotent (a 409 just means it already
# exists), so a brand-new project deploys unattended instead of dying here.
echo "NOTE: Initializing Identity Platform (idempotent)..."
init_code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  "https://identitytoolkit.googleapis.com/v2/projects/${project_id}/identityPlatform:initializeAuth" \
  -H "Authorization: Bearer ${access_token}" \
  -H "X-Goog-User-Project: ${project_id}" \
  -H "Content-Type: application/json" \
  -d '{}')
case "${init_code}" in
  2*)  echo "NOTE: Identity Platform initialized." ;;
  409) echo "NOTE: Identity Platform already initialized." ;;
  *)   echo "WARN: initializeAuth returned HTTP ${init_code} — continuing (may already be set up)." ;;
esac

# Enable email/password sign-in. Capture the status so an HTTP error surfaces the
# response body and aborts loudly — the old `curl -sf ... >/dev/null` swallowed a
# 404 and exited with no output, which is impossible to debug.
echo "NOTE: Enabling Identity Platform email/password sign-in..."
resp=$(curl -sS -w $'\n%{http_code}' -X PATCH \
  "https://identitytoolkit.googleapis.com/v2/projects/${project_id}/config?updateMask=signIn.email.enabled,signIn.email.passwordRequired" \
  -H "Authorization: Bearer ${access_token}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${project_id}" \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}')
patch_code=$(printf '%s' "${resp}" | tail -n1)
patch_body=$(printf '%s' "${resp}" | sed '$d')
if [ "${patch_code}" -ge 400 ]; then
  echo "ERROR: Identity Platform config PATCH failed (HTTP ${patch_code}):"
  echo "${patch_body}"
  exit 1
fi
echo "NOTE: Identity Platform configured."

echo "NOTE: Ensuring Firestore database exists in native mode..."
gcloud firestore databases create \
  --location=us-central1 \
  --type=firestore-native \
  --database="(default)" 2>/dev/null \
  || echo "NOTE: Firestore database already exists."

echo "NOTE: API setup complete."
