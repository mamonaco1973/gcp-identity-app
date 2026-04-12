"""
notes/main.py — Cloud Function entry point for the Notes CRUD API.

This module implements a single Cloud Functions 2nd Gen HTTP function (`notes`)
that handles all five REST operations for a simple note-taking application.
Rather than deploying one function per route, a single function inspects
`request.method` and `request.path` to dispatch internally — eliminating the
need for a separate API Gateway layer.

Routing table:
    POST   /notes          → _create(request)
    GET    /notes          → _list()
    GET    /notes/{id}     → _get(note_id)
    PUT    /notes/{id}     → _update(request, note_id)
    DELETE /notes/{id}     → _delete(note_id)
    OPTIONS *              → CORS preflight (204 No Content)

Storage:
    Google Cloud Firestore (Native mode) is used as the persistence layer.
    All notes are stored in the "notes" collection, keyed by a UUID4 string.
    The Firestore client is initialised once at module load time so that it is
    reused across warm invocations, avoiding the overhead of re-authenticating
    on every request.

Authentication:
    The function runs under a dedicated service account (notes-sa) that has
    been granted the roles/datastore.user role.  Application Default Credentials
    (ADC) are used automatically — no explicit credential handling is required
    inside the function code.

CORS:
    Cross-Origin Resource Sharing headers are attached to every response so
    that the static web frontend (served from a different GCS origin) can call
    the API directly from the browser.  The allowed origin is configurable via
    the CORS_ALLOW_ORIGIN environment variable; it defaults to "*" for the demo.

Environment variables:
    CORS_ALLOW_ORIGIN   The value of the Access-Control-Allow-Origin header.
                        Defaults to "*".  Set to the specific frontend origin
                        in production to restrict cross-origin access.
"""

import json
import os
import uuid
from datetime import datetime, timezone

from google.cloud import firestore

# ---------------------------------------------------------------------------
# Module-level singletons
# ---------------------------------------------------------------------------

# Firestore client.  Initialised once per function instance so the TCP
# connection and authentication token are reused across warm invocations.
db = firestore.Client()

# Name of the Firestore collection that stores all notes.
COLLECTION = "notes"

# Hard-coded owner value used to scope list queries.  In a real multi-user
# system this would come from a verified authentication token; for this demo
# every note is owned by the single synthetic user "global".
OWNER = "global"

# Value of the Access-Control-Allow-Origin response header.  Pulled from the
# environment so it can be overridden at deploy time without changing code.
CORS_ORIGIN = os.environ.get("CORS_ALLOW_ORIGIN", "*")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _cors_headers():
    """Return a dict of CORS headers to attach to every HTTP response.

    These headers allow the static web frontend — served from a Cloud Storage
    bucket on a different origin — to call this function directly from the
    browser without being blocked by the same-origin policy.

    Returns:
        dict: A dictionary containing the three CORS response headers:
            - Access-Control-Allow-Origin: controls which origins may read
              the response (defaults to "*" for the demo).
            - Access-Control-Allow-Methods: the HTTP verbs the browser is
              permitted to use in a cross-origin request.
            - Access-Control-Allow-Headers: the request headers the browser
              is permitted to send (Content-Type is required for JSON POST/PUT).
    """
    return {
        "Access-Control-Allow-Origin": CORS_ORIGIN,
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    }


def _json(data, status=200):
    """Serialise `data` to JSON and return a Cloud Functions HTTP response tuple.

    Cloud Functions 2nd Gen accepts a 3-tuple of (body, status_code, headers)
    as a valid return value from an HTTP-triggered function.  This helper
    centralises JSON serialisation and ensures CORS headers are present on
    every response.

    Args:
        data (dict | list): The response payload.  Must be JSON-serialisable.
        status (int): The HTTP status code to return.  Defaults to 200.

    Returns:
        tuple: (json_string, status_code, headers_dict) suitable for returning
        directly from the Cloud Function entry point.
    """
    return (json.dumps(data), status, {**_cors_headers(), "Content-Type": "application/json"})


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def notes(request):
    """Cloud Function entry point — routes incoming HTTP requests to handlers.

    This is the function registered as the Cloud Functions entry point in
    Terraform (entry_point = "notes").  Cloud Functions 2nd Gen exposes the
    full request path, so sub-path routing is done here without an API Gateway.

    Path parsing logic:
        The function is deployed at:
            https://us-central1-{project}.cloudfunctions.net/notes
        Cloud Functions 2nd Gen passes everything *after* the function name as
        request.path.  A request to /notes produces request.path = "/", while
        a request to /notes/abc123 produces request.path = "/abc123".
        Stripping the leading slash leaves either an empty string (collection
        operation) or a document ID (item operation).

    Args:
        request (flask.Request): The incoming HTTP request object provided by
            the Cloud Functions framework.  Relevant attributes used here:
            - request.method (str): The HTTP verb (GET, POST, PUT, DELETE, OPTIONS).
            - request.path (str): The URL path segment after the function name.

    Returns:
        tuple: A 3-tuple of (body, status_code, headers) produced by `_json()`
        or the CORS preflight response.
    """
    # Handle CORS preflight requests.  Browsers send an OPTIONS request before
    # any cross-origin POST/PUT/DELETE to verify the server allows the call.
    # Returning 204 with the appropriate headers satisfies the preflight check
    # and allows the browser to proceed with the real request.
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    # Derive whether this is a collection-level or document-level operation.
    # request.path is "/" for the collection root and "/{id}" for a specific
    # document; stripping the slash gives "" or "{id}" respectively.
    path = request.path.strip("/")
    note_id = path if path else None

    # Dispatch to the appropriate handler based on method + presence of an ID.
    if request.method == "POST" and note_id is None:
        return _create(request)
    if request.method == "GET" and note_id is None:
        return _list()
    if request.method == "GET" and note_id:
        return _get(note_id)
    if request.method == "PUT" and note_id:
        return _update(request, note_id)
    if request.method == "DELETE" and note_id:
        return _delete(note_id)

    # No route matched — return 404.
    return _json({"error": "Not found"}, 404)


# ---------------------------------------------------------------------------
# CRUD handlers
# ---------------------------------------------------------------------------

def _create(request):
    """Create a new note and persist it to Firestore.

    Reads `title` and `note` from the JSON request body, generates a UUID4
    as the document key, records creation and update timestamps, and writes
    the document to Firestore with document.set().

    Request body (JSON):
        {
            "title": "string (required)",
            "note":  "string (required)"
        }

    Firestore document written:
        {
            "owner":      "global",
            "id":         "<uuid4>",
            "title":      "<title>",
            "note":       "<note>",
            "created_at": "<ISO-8601 UTC>",
            "updated_at": "<ISO-8601 UTC>"
        }

    Args:
        request (flask.Request): The incoming HTTP request.  The JSON body is
            read with get_json(silent=True); if the body is missing or not
            valid JSON, an empty dict is used and validation catches it.

    Returns:
        tuple: 201 with {"id", "title", "note"} on success.
               400 if title or note are missing/empty.
               500 if the Firestore write raises an exception.
    """
    try:
        body = request.get_json(silent=True) or {}
        title = body.get("title", "").strip()
        note = body.get("note", "").strip()

        # Both fields are required — reject incomplete payloads early.
        if not title or not note:
            return _json({"error": "title and note are required"}, 400)

        # Generate a UUID4 that serves as both the Firestore document ID and
        # the `id` field stored inside the document so clients can reference
        # the note by ID without needing to parse the document path.
        note_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        item = {
            "owner":      OWNER,
            "id":         note_id,
            "title":      title,
            "note":       note,
            "created_at": now,
            "updated_at": now,
        }

        # document().set() creates the document if it does not exist or
        # overwrites it entirely if it does.  Because the ID is freshly
        # generated, a collision is astronomically unlikely.
        db.collection(COLLECTION).document(note_id).set(item)

        # Return only the fields the client needs to reference the new note.
        return _json({"id": note_id, "title": title, "note": note}, 201)

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _list():
    """List all notes belonging to the current owner.

    Queries the Firestore `notes` collection for every document whose `owner`
    field matches OWNER ("global") and returns them as a JSON array.  The
    where() filter is intentionally simple for the demo; a production system
    would filter by an authenticated user ID instead.

    Returns:
        tuple: 200 with {"items": [<note>, ...]} where each note is the full
               Firestore document dict (owner, id, title, note, created_at,
               updated_at).
               500 if the Firestore query raises an exception.
    """
    try:
        # stream() lazily iterates the query results, converting each
        # DocumentSnapshot to a plain Python dict via to_dict().
        docs = db.collection(COLLECTION).where("owner", "==", OWNER).stream()
        items = [doc.to_dict() for doc in docs]
        return _json({"items": items})

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _get(note_id):
    """Retrieve a single note by its document ID.

    Performs a direct document lookup by ID rather than a collection query,
    which is faster and guaranteed strongly consistent in Firestore Native mode.

    Args:
        note_id (str): The UUID4 document ID extracted from the request path.

    Returns:
        tuple: 200 with the full note dict on success.
               404 if no document with the given ID exists.
               500 if the Firestore read raises an exception.
    """
    try:
        doc = db.collection(COLLECTION).document(note_id).get()

        # doc.exists is False when Firestore returns an empty DocumentSnapshot,
        # meaning no document with this ID was found in the collection.
        if not doc.exists:
            return _json({"error": "Note not found"}, 404)

        return _json(doc.to_dict())

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _update(request, note_id):
    """Update the title and note body of an existing note.

    Reads `title` and `note` from the JSON request body, verifies the document
    exists, then uses document.update() to patch only the changed fields
    (title, note, updated_at) without overwriting created_at or owner.

    Args:
        request (flask.Request): The incoming HTTP request.  The JSON body
            must contain `title` and `note`.
        note_id (str): The UUID4 document ID extracted from the request path.

    Returns:
        tuple: 200 with the full updated note dict on success.
               400 if title or note are missing/empty.
               404 if no document with the given ID exists.
               500 if any Firestore operation raises an exception.
    """
    try:
        body = request.get_json(silent=True) or {}
        title = body.get("title", "").strip()
        note = body.get("note", "").strip()

        if not title or not note:
            return _json({"error": "title and note are required"}, 400)

        ref = db.collection(COLLECTION).document(note_id)

        # Verify the document exists before attempting an update.  Firestore's
        # update() would raise an exception on a missing document, but checking
        # explicitly lets us return a clean 404 instead of a 500.
        if not ref.get().exists:
            return _json({"error": "Note not found"}, 404)

        now = datetime.now(timezone.utc).isoformat()

        # update() performs a partial write — only the specified fields are
        # changed; all other fields (owner, id, created_at) are left intact.
        ref.update({"title": title, "note": note, "updated_at": now})

        # Re-fetch the document to return the authoritative post-update state.
        return _json(ref.get().to_dict())

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _delete(note_id):
    """Delete a note by its document ID.

    Verifies the document exists before deleting so that attempts to delete a
    non-existent note return a 404 rather than silently succeeding (Firestore's
    delete() is a no-op on a missing document).

    Args:
        note_id (str): The UUID4 document ID extracted from the request path.

    Returns:
        tuple: 200 with {"message": "Note deleted"} on success.
               404 if no document with the given ID exists.
               500 if any Firestore operation raises an exception.
    """
    try:
        ref = db.collection(COLLECTION).document(note_id)

        # Existence check before delete so callers receive a meaningful 404
        # instead of a 200 that implies the note was actually removed.
        if not ref.get().exists:
            return _json({"error": "Note not found"}, 404)

        ref.delete()
        return _json({"message": "Note deleted"})

    except Exception as e:
        return _json({"error": str(e)}, 500)
