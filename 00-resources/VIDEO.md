#GCP #Serverless #CloudFunctions #Firestore #Terraform #Python #CRUD

*Build a Serverless CRUD API on Google Cloud (Cloud Functions + Firestore)*

Deploy a fully serverless notes API on Google Cloud Platform using Terraform, Cloud Functions 2nd Gen, and Firestore. The backend runs on a single Python Cloud Function that routes all CRUD operations internally, backed by a Firestore Native mode database, with a static web frontend served directly from Cloud Storage.

In this project we build a clean REST API with full Create, Read, Update, and Delete support — wired to a real database, deployed with a single script, and tested through a browser-based UI with no server to manage.

WHAT YOU'LL LEARN
• Deploying Cloud Functions 2nd Gen with Terraform using google_cloudfunctions2_function
• Packaging and uploading Python source code to GCS with archive_file and a source bucket
• Provisioning Firestore (Native mode) and routing all five CRUD operations in a single function
• Hosting a static web frontend on a public GCS bucket
• Injecting runtime config into HTML templates using envsubst

INFRASTRUCTURE DEPLOYED
• Cloud Function (2nd Gen, Python 3.11, HTTP trigger, public via allUsers run.invoker)
• GCS bucket for function source code (zip archive, content-addressed)
• Firestore database (Native mode, us-central1)
• Service account (notes-sa) with scoped roles/datastore.user
• GCS bucket hosting a static web frontend

GitHub
https://github.com/mamonaco1973/gcp-crud-example

README
https://github.com/mamonaco1973/gcp-crud-example/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:17 Architecture
00:43 Build the Code
00:58 Build Results
01:22 Demo
