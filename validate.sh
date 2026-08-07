#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL=$(jq -r '.apiBaseUrl' 02-webapp/config.json)
WEBAPP_URL=$(cd 02-webapp && terraform output -raw webapp_url 2>/dev/null || echo "N/A")

echo ""
echo "================================================================================="
echo "  Deployment complete!"
echo "================================================================================="
echo "  API     : ${GATEWAY_URL}/notes"
echo "  Web app : ${WEBAPP_URL}"
echo "================================================================================="

# ─── Google Sign-In — OAuth 2.0 Web client settings ──────────────────────────
# "Sign in with Google" uses an OAuth 2.0 Web client you create in the Console.
# Google won't accept the login flow until these two fields match our deploy, so
# print the exact values to paste in. The redirect goes to Firebase's hosted auth
# handler (authDomain), not our app; the JS origin is where the SPA is served.
PROJECT_ID=$(jq -r '.projectId'  02-webapp/config.json)
AUTH_DOMAIN=$(jq -r '.authDomain' 02-webapp/config.json)   # <project>.firebaseapp.com
WEBAPP_ORIGIN=$(echo "${WEBAPP_URL}" | sed -E 's#(https?://[^/]+).*#\1#')
# webapp_url is "N/A" if the TF output wasn't readable — fall back to the GCS host
[[ "${WEBAPP_ORIGIN}" =~ ^https?:// ]] || WEBAPP_ORIGIN="https://storage.googleapis.com"

echo ""
echo "================================================================================="
echo "  Google IdP — OAuth 2.0 Web client (Console → APIs & Services → Credentials)"
echo "================================================================================="
echo "  Authorized JavaScript origins:"
echo "      ${WEBAPP_ORIGIN}"
echo "      https://${AUTH_DOMAIN}"
echo ""
echo "  Authorized redirect URIs:"
echo "      https://${AUTH_DOMAIN}/__/auth/handler"
echo "================================================================================="
