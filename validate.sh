#!/usr/bin/env bash
set -euo pipefail

# Read deploy-time config
FIREBASE_API_KEY=$(jq -r '.apiKey'     02-webapp/config.json)
GATEWAY_URL=$(jq -r '.apiBaseUrl'      02-webapp/config.json)
NOTES_URL="${GATEWAY_URL}/notes"

echo "NOTE: Validating API at ${NOTES_URL}"

# ─── Verify gateway rejects unauthenticated requests ─────────────────────────

wait_for_gateway() {
  for attempt in {1..10}; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${NOTES_URL}")
    if [[ "${HTTP_STATUS}" == "401" || "${HTTP_STATUS}" == "403" ]]; then
      echo "NOTE: Gateway is up (returned ${HTTP_STATUS} for unauthenticated request)."
      return 0
    fi
    if [[ "${attempt}" -eq 10 ]]; then
      echo "ERROR: Gateway did not become ready after 10 attempts (last status: ${HTTP_STATUS})."
      exit 1
    fi
    echo "NOTE: Gateway not ready (attempt ${attempt}, status ${HTTP_STATUS}), retrying in 10 seconds..."
    sleep 10
  done
}

wait_for_gateway

# ─── Create a temporary test user via Identity Platform REST API ─────────────

TEST_EMAIL="validate-$(date +%s)@example.com"
TEST_PASSWORD="TestPassword123!"

echo "NOTE: Creating test user ${TEST_EMAIL}..."
SIGNUP_RESPONSE=$(curl -sf -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FIREBASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${TEST_EMAIL}\",\"password\":\"${TEST_PASSWORD}\",\"returnSecureToken\":true}") \
  || { echo "ERROR: Failed to create test user"; exit 1; }

ID_TOKEN=$(echo "${SIGNUP_RESPONSE}" | jq -r '.idToken')
if [[ -z "${ID_TOKEN}" || "${ID_TOKEN}" == "null" ]]; then
  echo "ERROR: Could not obtain ID token. Response: ${SIGNUP_RESPONSE}"
  exit 1
fi
echo "NOTE: Test user created."

AUTH_HEADER="Authorization: Bearer ${ID_TOKEN}"

# ─── Create 5 notes ──────────────────────────────────────────────────────────

echo "NOTE: Creating 5 test notes..."
NOTE_IDS=()

for i in {1..5}; do
  PAYLOAD=$(jq -n --arg title "Test Note ${i}" --arg note "This is test note ${i}" \
    '{ title: $title, note: $note }')

  RESPONSE=$(curl -sf -X POST "${NOTES_URL}" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}" \
    -d "${PAYLOAD}") || { echo "ERROR: POST request failed for note ${i}"; exit 1; }

  NOTE_ID=$(echo "${RESPONSE}" | jq -r '.id // empty')
  if [[ -z "${NOTE_ID}" ]]; then
    echo "ERROR: Failed to create note ${i}. Response: ${RESPONSE}"
    exit 1
  fi

  NOTE_IDS+=("${NOTE_ID}")
  echo "NOTE: Created note ${i} (id=${NOTE_ID})"
done

# ─── List notes ──────────────────────────────────────────────────────────────

echo "NOTE: Listing notes..."
LIST_RESPONSE=$(curl -sf "${NOTES_URL}" \
  -H "${AUTH_HEADER}") || { echo "ERROR: GET /notes request failed"; exit 1; }
NOTE_COUNT=$(echo "${LIST_RESPONSE}" | jq '.items | length')

if [[ "${NOTE_COUNT}" -lt 5 ]]; then
  echo "ERROR: Expected at least 5 notes, got ${NOTE_COUNT}"
  exit 1
fi
echo "NOTE: List endpoint returned ${NOTE_COUNT} notes"

# ─── Get each note ────────────────────────────────────────────────────────────

echo "NOTE: Fetching each note by ID..."
for ID in "${NOTE_IDS[@]}"; do
  TITLE=$(curl -sf "${NOTES_URL}/${ID}" \
    -H "${AUTH_HEADER}" | jq -r '.title // empty') \
    || { echo "ERROR: GET /notes/${ID} request failed"; exit 1; }
  if [[ -z "${TITLE}" ]]; then
    echo "ERROR: Failed to fetch note ${ID}"
    exit 1
  fi
  echo "NOTE: Retrieved note ${ID} (${TITLE})"
done

# ─── Update each note ─────────────────────────────────────────────────────────

echo "NOTE: Updating each note..."
for ID in "${NOTE_IDS[@]}"; do
  UPDATE_PAYLOAD=$(jq -n \
    --arg title "Updated Title" \
    --arg note "Updated body for ${ID}" \
    '{ title: $title, note: $note }')

  UPDATED_TITLE=$(curl -sf -X PUT "${NOTES_URL}/${ID}" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}" \
    -d "${UPDATE_PAYLOAD}" | jq -r '.title // empty') \
    || { echo "ERROR: PUT /notes/${ID} request failed"; exit 1; }

  if [[ -z "${UPDATED_TITLE}" ]]; then
    echo "ERROR: Failed to update note ${ID}"
    exit 1
  fi
  echo "NOTE: Updated note ${ID}"
done

# ─── Delete each note ─────────────────────────────────────────────────────────

echo "NOTE: Deleting each note..."
for ID in "${NOTE_IDS[@]}"; do
  curl -sf -X DELETE "${NOTES_URL}/${ID}" \
    -H "${AUTH_HEADER}" > /dev/null \
    || { echo "ERROR: DELETE /notes/${ID} request failed"; exit 1; }
  echo "NOTE: Deleted note ${ID}"
done

# ─── Cleanup: delete test user ────────────────────────────────────────────────

echo "NOTE: Deleting test user..."
curl -sf -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${FIREBASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"idToken\":\"${ID_TOKEN}\"}" > /dev/null \
  || echo "WARNING: Could not delete test user (manual cleanup may be needed)."
echo "NOTE: Test user deleted."

# ─── Summary ──────────────────────────────────────────────────────────────────

WEBAPP_URL=$(cd 02-webapp && terraform output -raw webapp_url 2>/dev/null || echo "N/A")

echo ""
echo "================================================================================="
echo "  Deployment validated!"
echo "================================================================================="
echo "  API     : ${NOTES_URL}"
echo "  Web app : ${WEBAPP_URL}"
echo "================================================================================="
