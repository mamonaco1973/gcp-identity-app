#!/usr/bin/env bash
set -euo pipefail

echo "NOTE: Running environment validation..."
./check_env.sh

# ─── Phase 1: Backend (Cloud Function + Identity Platform + API Gateway) ─────

echo "NOTE: Deploying backend infrastructure..."
cd 01-functions
terraform init -input=false
# Google sign-in provider is provisioned only when these env vars are set
# (see variables.tf / identity.tf). Unset => email/password only.
terraform apply -auto-approve \
  -var="google_oauth_client_id=${GOOGLE_OAUTH_CLIENT_ID:-}" \
  -var="google_oauth_client_secret=${GOOGLE_OAUTH_CLIENT_SECRET:-}"

GATEWAY_URL=$(terraform output -raw gateway_url)
FIREBASE_API_KEY=$(terraform output -raw firebase_api_key)
cd ..

project_id=$(jq -r '.project_id' credentials.json)
echo "NOTE: Gateway URL   = ${GATEWAY_URL}"
echo "NOTE: API key ready."

# ─── Generate webapp config ──────────────────────────────────────────────────

echo "NOTE: Generating 02-webapp/config.json..."
cat > 02-webapp/config.json << EOF
{
  "apiKey":      "${FIREBASE_API_KEY}",
  "authDomain":  "${project_id}.firebaseapp.com",
  "projectId":   "${project_id}",
  "apiBaseUrl":  "${GATEWAY_URL}"
}
EOF

# index.html has no template variables — config is loaded at runtime from config.json.
echo "NOTE: Generating 02-webapp/index.html..."
cp 02-webapp/index.html.tmpl 02-webapp/index.html

# ─── Phase 2: Web Application ────────────────────────────────────────────────

echo "NOTE: Deploying web application..."
cd 02-webapp
terraform init -input=false
terraform apply -auto-approve
cd ..

# ─── Post-deploy validation ──────────────────────────────────────────────────

echo "NOTE: Running validation..."
./validate.sh
