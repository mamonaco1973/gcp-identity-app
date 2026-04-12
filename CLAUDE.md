# CLAUDE.md — gcp-crud-example

A serverless notes CRUD API on GCP. One Cloud Function handles all five REST operations, Firestore stores the data, and a static GCS site provides a browser UI. Ported from an equivalent AWS solution (Lambda + DynamoDB + API Gateway).

---

## What This Project Does

Clients hit a single Cloud Function (`notes`) that routes all HTTP CRUD operations by method and path. Firestore persists the notes. A static HTML frontend served from GCS makes API calls directly to the function.

**Base URL after deploy:**
```
https://us-central1-{project_id}.cloudfunctions.net/notes
```

| Method | Path | Operation |
|--------|------|-----------|
| POST | `/notes` | Create note |
| GET | `/notes` | List all notes |
| GET | `/notes/{id}` | Get single note |
| PUT | `/notes/{id}` | Update note |
| DELETE | `/notes/{id}` | Delete note |

---

## Architecture

```
Browser / curl
     │
     ▼
Cloud Function: notes  (Python 3.11, HTTP trigger, public)
     │  routes by request.method + request.path
     ├── POST   /        → _create()
     ├── GET    /        → _list()
     ├── GET    /{id}    → _get()
     ├── PUT    /{id}    → _update()
     └── DELETE /{id}    → _delete()
                │
                ▼
          Firestore (Native mode)
          collection: notes
          document key: UUID
```

**Why one function instead of five:** Cloud Functions 2nd Gen pass the full request path, so internal routing eliminates the need for a separate API Gateway layer. The function named `notes` sits at `.../notes`, and any sub-path (e.g., `.../notes/abc123`) appears as `request.path = "/abc123"`.

---

## Repository Layout

```
01-functions/
  notes/
    main.py           Python: all five CRUD handlers + router
    requirements.txt  google-cloud-firestore
  main.tf             Terraform: provider, SA, GCS source bucket, function, IAM
02-webapp/
  index.html.tmpl     Web UI template — API_BASE injected at deploy time
  main.tf             Terraform: GCP provider
  public-bucket.tf    Terraform: public GCS static site
api_setup.sh          Enable GCP APIs, create Firestore database
check_env.sh          Pre-flight: verify gcloud/terraform/jq, credentials.json
apply.sh              Full deployment (both phases + validation)
destroy.sh            Teardown in reverse order
validate.sh           End-to-end CRUD smoke test via curl
```

---

## Prerequisites

- `gcloud`, `terraform`, `jq` in PATH
- `credentials.json` (GCP service account key) in repo root
- Service account needs: Cloud Functions, Firestore, Cloud Storage, Cloud Run, Cloud Build, IAM

---

## Deployment

```bash
# Full deploy
./apply.sh

# Teardown
./destroy.sh

# Smoke test only (after deploy)
./validate.sh
```

`apply.sh` runs in two phases:
1. **`check_env.sh`** → validates tools, authenticates gcloud, calls `api_setup.sh` to enable APIs and init Firestore
2. **`01-functions`** → archives Python source, uploads to GCS, deploys Cloud Function, creates service account
3. Injects `API_BASE` into `index.html.tmpl` via `envsubst`
4. **`02-webapp`** → deploys public GCS bucket, uploads generated `index.html`
5. **`validate.sh`** → creates, lists, gets, updates, and deletes 5 test notes

---

## Terraform Modules

### 01-functions
- `google_service_account` `notes-sa` with `roles/datastore.user`
- `google_storage_bucket` for function source code (random suffix)
- `data.archive_file` zips the `notes/` directory; re-zips on any source change
- `google_cloudfunctions2_function` `notes` (Python 3.11, 2nd Gen, HTTP)
- `google_cloud_run_service_iam_member` — `allUsers` → `roles/run.invoker` (public)
- Output: `notes_url`

### 02-webapp
- `google_storage_bucket` `notes-web-{suffix}` with public read
- `google_storage_bucket_object` uploads `index.html` (generated from template)
- Output: `webapp_url`

---

## Cloud Function Routing

**File:** [01-functions/notes/main.py](01-functions/notes/main.py)

Entry point `notes(request)` dispatches based on `request.method` and `request.path.strip("/")`:

```
request.path = "/"      → collection operations (POST → create, GET → list)
request.path = "/{id}"  → item operations (GET → get, PUT → update, DELETE → delete)
```

CORS preflight (`OPTIONS`) is handled first and returns 204 with appropriate headers.

**Firestore data model:**
- Collection: `notes`
- Document ID: UUID4 (same as `id` field)
- Fields: `owner` (always `"global"`), `id`, `title`, `note`, `created_at`, `updated_at`

---

## Web UI

`02-webapp/index.html.tmpl` is a single-page JavaScript app. It uses `${API_BASE}` as a placeholder replaced at deploy time by `apply.sh` via `envsubst`:

```bash
export API_BASE="https://us-central1-${project_id}.cloudfunctions.net"
envsubst '${API_BASE}' < 02-webapp/index.html.tmpl > 02-webapp/index.html
```

The JS calls `API_BASE_URL + "/notes"` and `API_BASE_URL + "/notes/" + id`, which map directly to the `notes` function URL and its sub-paths.

---

## Test Manually

```bash
BASE="https://us-central1-$(jq -r '.project_id' credentials.json).cloudfunctions.net/notes"

# Create
curl -X POST "$BASE" -H "Content-Type: application/json" \
  -d '{"title":"Hello","note":"World"}'

# List
curl "$BASE"

# Get / Update / Delete (replace ID)
curl "$BASE/{id}"
curl -X PUT "$BASE/{id}" -H "Content-Type: application/json" \
  -d '{"title":"Updated","note":"Body"}'
curl -X DELETE "$BASE/{id}"
```
