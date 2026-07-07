#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_apphosting_env_vars.sh
set -e

cat > "apphosting.yaml" << 'VS_APPLY_EOF_ah1'
env:
  # ── Secrets (already set via `firebase apphosting:secrets:set`) ──────────
  - variable: ANTHROPIC_API_KEY
    secret: ANTHROPIC_API_KEY
    availability: [BUILD, RUNTIME]
  - variable: GOOGLE_CLIENT_SECRET
    secret: GOOGLE_CLIENT_SECRET
    availability: [BUILD, RUNTIME]
  - variable: GOOGLE_DOCO_REFRESH_TOKEN
    secret: GOOGLE_DOCO_REFRESH_TOKEN
    availability: [BUILD, RUNTIME]
  - variable: ADMIN_PRIVATE_KEY
    secret: FIREBASE_ADMIN_PRIVATE_KEY
    availability: [BUILD, RUNTIME]

  # ── Plain config (not secret) — replace each REPLACE_ME with the value ───
  # ── from the same-named line in your .env.local, then save this file. ────
  - variable: NEXT_PUBLIC_FIREBASE_API_KEY
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NEXT_PUBLIC_FIREBASE_PROJECT_ID
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NEXT_PUBLIC_FIREBASE_APP_ID
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NEXT_PUBLIC_ALLOWED_DOMAIN
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: ADMIN_PROJECT_ID
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: ADMIN_CLIENT_EMAIL
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: GOOGLE_CLIENT_ID
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: GOOGLE_REDIRECT_URI
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: CLAUDE_MODEL
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: DRIVE_ROOT_FOLDER_ID
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: DRIVE_SERVICE_ACCOUNT_EMAIL
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
  - variable: NOTIFY_EMAIL_PRIMARY
    value: "REPLACE_ME"
    availability: [BUILD, RUNTIME]
VS_APPLY_EOF_ah1

echo ""
echo "Done. apphosting.yaml written with placeholders."
echo ""
echo "IMPORTANT: this file gets committed to your repo (App Hosting reads it"
echo "from GitHub), so only put non-secret values in it — which is true of"
echo "everything left as a placeholder here. Open apphosting.yaml now and"
echo "replace each \"REPLACE_ME\" with the matching value from .env.local."
echo ""
echo "Also double check GOOGLE_REDIRECT_URI once you know your production"
echo "URL — it likely needs to point at your deployed domain, not localhost,"
echo "and that URL also needs to be added as an authorized redirect URI in"
echo "the Google Cloud Console OAuth client."
