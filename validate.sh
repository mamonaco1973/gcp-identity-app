#!/usr/bin/env bash
set -euo pipefail

project_id=$(jq -r '.project_id' credentials.json)
NOTES_URL="https://us-central1-${project_id}.cloudfunctions.net/notes"

echo "NOTE: Validating API at ${NOTES_URL}"

# ─── Wait for API to be ready ───────────────────────────────────────────────────
wait_for_api() {
  for attempt in {1..10}; do
    if curl -sf "${NOTES_URL}" > /dev/null 2>&1; then
      return 0
    fi
    if [[ "${attempt}" -eq 10 ]]; then
      echo "ERROR: API did not become ready after 10 attempts."
      exit 1
    fi
    echo "NOTE: API not ready (attempt ${attempt}), retrying in 10 seconds..."
    sleep 10
  done
}

# ─── Create 5 notes ─────────────────────────────────────────────────────────────
echo "NOTE: Creating 5 test notes..."
NOTE_IDS=()

for i in {1..5}; do
  PAYLOAD=$(jq -n --arg title "Test Note ${i}" --arg note "This is test note ${i}" \
    '{ title: $title, note: $note }')

  wait_for_api
  RESPONSE=$(curl -sf -X POST "${NOTES_URL}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}") || { echo "ERROR: POST request failed for note ${i}"; exit 1; }

  NOTE_ID=$(echo "${RESPONSE}" | jq -r '.id // empty')
  if [[ -z "${NOTE_ID}" ]]; then
    echo "ERROR: Failed to create note ${i}. Response: ${RESPONSE}"
    exit 1
  fi

  NOTE_IDS+=("${NOTE_ID}")
  echo "NOTE: Created note ${i} (id=${NOTE_ID})"
done

# ─── List notes ─────────────────────────────────────────────────────────────────
echo "NOTE: Listing notes..."
wait_for_api
LIST_RESPONSE=$(curl -sf "${NOTES_URL}") || { echo "ERROR: GET /notes request failed"; exit 1; }
NOTE_COUNT=$(echo "${LIST_RESPONSE}" | jq '.items | length')

if [[ "${NOTE_COUNT}" -lt 5 ]]; then
  echo "ERROR: Expected at least 5 notes, got ${NOTE_COUNT}"
  exit 1
fi
echo "NOTE: List endpoint returned ${NOTE_COUNT} notes"

# ─── Get each note ───────────────────────────────────────────────────────────────
echo "NOTE: Fetching each note by ID..."
for ID in "${NOTE_IDS[@]}"; do
  wait_for_api
  TITLE=$(curl -sf "${NOTES_URL}/${ID}" | jq -r '.title // empty') || { echo "ERROR: GET /notes/${ID} request failed"; exit 1; }
  if [[ -z "${TITLE}" ]]; then
    echo "ERROR: Failed to fetch note ${ID}"
    exit 1
  fi
  echo "NOTE: Retrieved note ${ID} (${TITLE})"
done

# ─── Update each note ────────────────────────────────────────────────────────────
echo "NOTE: Updating each note..."
for ID in "${NOTE_IDS[@]}"; do
  UPDATE_PAYLOAD=$(jq -n \
    --arg title "Updated Title" \
    --arg note "Updated body for ${ID}" \
    '{ title: $title, note: $note }')

  wait_for_api
  UPDATED_TITLE=$(curl -sf -X PUT "${NOTES_URL}/${ID}" \
    -H "Content-Type: application/json" \
    -d "${UPDATE_PAYLOAD}" | jq -r '.title // empty') || { echo "ERROR: PUT /notes/${ID} request failed"; exit 1; }

  if [[ -z "${UPDATED_TITLE}" ]]; then
    echo "ERROR: Failed to update note ${ID}"
    exit 1
  fi
  echo "NOTE: Updated note ${ID}"
done

# ─── Delete each note ────────────────────────────────────────────────────────────
echo "NOTE: Deleting each note..."
for ID in "${NOTE_IDS[@]}"; do
  wait_for_api
  curl -sf -X DELETE "${NOTES_URL}/${ID}" > /dev/null || { echo "ERROR: DELETE /notes/${ID} request failed"; exit 1; }
  echo "NOTE: Deleted note ${ID}"
done

# ─── Summary ─────────────────────────────────────────────────────────────────────
WEBAPP_URL=$(cd 02-webapp && terraform output -raw webapp_url 2>/dev/null || echo "N/A")

echo ""
echo "================================================================================="
echo "  Deployment validated!"
echo "================================================================================="
echo "  API : ${NOTES_URL}"
echo "  Web : ${WEBAPP_URL}"
echo "================================================================================="
