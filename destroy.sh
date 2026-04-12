#!/usr/bin/env bash
set -euo pipefail

project_id=$(jq -r '.project_id' credentials.json)
NOTES_URL="https://us-central1-${project_id}.cloudfunctions.net/notes"

# ─── Delete all notes via API ────────────────────────────────────────────────────
echo "NOTE: Deleting all notes via API..."
LIST_RESPONSE=$(curl -sf "${NOTES_URL}") || { echo "ERROR: GET /notes request failed"; exit 1; }
NOTE_IDS=$(echo "${LIST_RESPONSE}" | jq -r '.items[]?.id // empty')

doc_count=0
while IFS= read -r id; do
  [[ -z "${id}" ]] && continue
  curl -sf -X DELETE "${NOTES_URL}/${id}" > /dev/null || { echo "ERROR: DELETE /notes/${id} failed"; exit 1; }
  echo "NOTE: Deleted note ${id}"
  doc_count=$((doc_count + 1))
done <<< "${NOTE_IDS}"
echo "NOTE: Deleted ${doc_count} document(s) from notes collection."

# ─── Destroy infrastructure ──────────────────────────────────────────────────────
echo "NOTE: Destroying web application..."
cd 02-webapp
terraform destroy -auto-approve
cd ..

echo "NOTE: Destroying Cloud Function and infrastructure..."
cd 01-functions
terraform destroy -auto-approve
cd ..

echo "NOTE: Destroy complete."
