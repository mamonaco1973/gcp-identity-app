# Video Script — Serverless CRUD API on GCP with Cloud Functions and Firestore

---

## Introduction

[ Screen recording of the Notes Demo web app — creating, editing, and deleting notes in the browser ]

"Do you need a working serverless API on Google Cloud?

[ Architecture diagram — walk through it left to right: browser, Cloud Storage, Cloud Function, Firestore ]

"In this project we build a fully serverless notes API using Cloud Functions, Firestore, and Cloud Storage — all provisioned with Terraform and deployed with a single script."

[Terminal running apply.sh — Terraform output flying by, ending with the website URL ]

"Follow along and in minutes you'll have a working API running on Google Cloud."

---

## Architecture

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Highlight browser and Cloud Storage bucket ]

"The user opens a static web page — which is just an HTML file served directly from a public Cloud Storage bucket."

[ Highlight Cloud Function ]

"The frontend talks to a Cloud Functions over HTTPS. One Python file handles all the routes — POST to create, GET to list, GET by ID, PUT to update, DELETE to remove. "

[ Highlight Firestore ]

"The backend stores data in Firestore. Each note is a JSON document, and the Cloud Functions read and write directly to it."

---

## Build the Code

[ Terminal — running ./apply.sh ]

"The whole deployment is one script — apply.sh. Two phases."

[ Terminal — check_env.sh running, API enablement output ]

"First, check_env.sh validates your tools, authenticates gcloud, enables the required GCP APIs, and creates the Firestore database in native mode."

[ Terminal — Phase 1: Terraform apply in 01-functions ]

"Phase one: Terraform provisions the Cloud Function and its supporting infrastructure — a service account scoped to Firestore, a GCS bucket to hold the source zip, and the function itself wired to that bucket."

[ Terminal — Phase 2: envsubst then Terraform apply in 02-webapp ]

"Phase two: envsubst injects the Cloud Function base URL into the HTML template. Terraform creates a public Cloud Storage bucket and uploads the generated index.html — the site is live."

[ Terminal — deployment complete, URLs printed ]

"Function URL. Website URL. Done."

---

## Build Results

[ GCP Console — Cloud Functions ]

"The notes Cloud Functions are deployed and public. This is the compute layer for the API."

[ Show function details — runtime, entry point, trigger URL ]

"The Cloud Functions are implemented in Python, and the HTTP routes are handled directly in the code."

[ GCP Console — Firestore ]

"Next is Firestore. This is the storage layer for the API."

[ GCP Console — Cloud Storage, web bucket ]

"Finally, a public Cloud Storage bucket hosts the static web application."

[ Browser — Notes Demo loads ]

"Open the URL to launch the test application."

---

## Demo

[ Browser — Notes Demo, open DevTools → Network tab ]

"Open the web app — and the browser debugger so we can watch the API calls."

[ Refresh page — network calls visible ]

"When the app loads, it calls the list endpoint. No notes yet."

[ Clicking New — modal opens, typing a title, clicking Create ]

"Now let's create a new note by selecting New."

[ Show API working ]

"A POST to the function is made which returns the new note's UUID."

[ Clicking the note in the list ]

"The new note is also selected and the API loads the content."

[ Editing and clicking Save ]

"Now let's update the note and select Save."

[ Show network tab ]

"A PUT call is made — and the updated data is stored in Firestore."

[ Clicking Delete ]

"Now let's delete the note by selecting Delete."

[ Show network ]

"A DELETE call is made — and the document is removed from Firestore."

[ Browser — empty list ]

"In this demo, we've now exercised every API endpoint."

---
