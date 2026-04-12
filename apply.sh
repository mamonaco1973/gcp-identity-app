#!/usr/bin/env bash
set -euo pipefail

echo "NOTE: Running environment validation..."
./check_env.sh

# ─── Phase 1: Cloud Function + Firestore ────────────────────────────────────────

echo "NOTE: Deploying Cloud Function and Firestore..."
cd 01-functions
terraform init -input=false
terraform apply -auto-approve
cd ..

# ─── Phase 2: Web Application ────────────────────────────────────────────────────

project_id=$(jq -r '.project_id' credentials.json)
export API_BASE="https://us-central1-${project_id}.cloudfunctions.net"
echo "NOTE: API_BASE = ${API_BASE}"

echo "NOTE: Generating index.html from template..."
envsubst '${API_BASE}' < 02-webapp/index.html.tmpl > 02-webapp/index.html

echo "NOTE: Deploying web application..."
cd 02-webapp
terraform init -input=false
terraform apply -auto-approve
cd ..

# ─── Post-deploy validation ──────────────────────────────────────────────────────

echo "NOTE: Running validation..."
./validate.sh
