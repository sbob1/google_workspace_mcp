#!/usr/bin/env bash
# One-time infrastructure for the Workspace MCP Cloud Run service.
# Safe to re-run: every step checks before creating.
# Run from Cloud Shell, signed in as a project owner:  bash deploy/cloudrun/setup.sh
#
# Does NOT create the OAuth consent screen, the OAuth client, or its secret
# (CLIENT_SECRET_NAME in config.sh) — do those in the console first; see README.md.

set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

say() { printf '\n==> %s\n' "$*"; }

gcloud config set project "$PROJECT_ID" >/dev/null

say "Enabling required APIs (infrastructure + the Workspace APIs the tools call)"
gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com storage.googleapis.com iamcredentials.googleapis.com \
  billingbudgets.googleapis.com cloudscheduler.googleapis.com \
  gmail.googleapis.com drive.googleapis.com calendar-json.googleapis.com \
  docs.googleapis.com sheets.googleapis.com slides.googleapis.com forms.googleapis.com \
  tasks.googleapis.com people.googleapis.com chat.googleapis.com script.googleapis.com

say "Checking the OAuth client secret exists"
if ! gcloud secrets describe "$CLIENT_SECRET_NAME" >/dev/null 2>&1; then
  echo "Missing secret '$CLIENT_SECRET_NAME'. Create it in Secret Manager, then re-run." >&2
  exit 1
fi

say "Service accounts"
ensure_sa() {
  local name="$1" display="$2"
  if ! gcloud iam service-accounts describe "${name}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$name" --display-name="$display"
  fi
}
ensure_sa "$RUN_SA_NAME" "Workspace MCP runtime"
ensure_sa "$BUILD_SA_NAME" "Workspace MCP builder"
# New service accounts can take a few seconds before IAM accepts them.
sleep 10

say "Build service account: Cloud Run builder role"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${BUILD_SA}" --role="roles/run.builder" \
  --condition=None >/dev/null

say "Runtime service account may sign URLs as itself (for download links)"
gcloud iam service-accounts add-iam-policy-binding "$RUN_SA" \
  --member="serviceAccount:${RUN_SA}" --role="roles/iam.serviceAccountTokenCreator" >/dev/null

say "Buckets"
ensure_bucket() {
  local bucket="$1"
  if ! gcloud storage buckets describe "gs://${bucket}" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://${bucket}" \
      --location="$REGION" --uniform-bucket-level-access --public-access-prevention
  fi
  gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
    --member="serviceAccount:${RUN_SA}" --role="roles/storage.objectUser" >/dev/null
  gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
    --member="serviceAccount:${RUN_SA}" --role="roles/storage.bucketViewer" >/dev/null
}
ensure_bucket "$SESSIONS_BUCKET"
ensure_bucket "$FILES_BUCKET"

say "Files bucket: delete staged downloads after 1 day"
lifecycle_file="$(mktemp)"
cat >"$lifecycle_file" <<'JSON'
{"rule": [{"action": {"type": "Delete"}, "condition": {"age": 1}}]}
JSON
gcloud storage buckets update "gs://${FILES_BUCKET}" --lifecycle-file="$lifecycle_file" >/dev/null
rm -f "$lifecycle_file"

say "JWT signing key (generated here, never printed)"
if ! gcloud secrets describe "$JWT_SECRET_NAME" >/dev/null 2>&1; then
  openssl rand -hex 32 | tr -d '\n' | \
    gcloud secrets create "$JWT_SECRET_NAME" --replication-policy=automatic --data-file=-
fi

say "Runtime service account may read both secrets"
for secret in "$CLIENT_SECRET_NAME" "$JWT_SECRET_NAME"; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:${RUN_SA}" --role="roles/secretmanager.secretAccessor" >/dev/null
done

say "Keep-awake ping (Cloud Scheduler job ${KEEPWARM_JOB})"
keepwarm_flags=(
  --location="$REGION"
  --schedule="$KEEPWARM_SCHEDULE"
  --uri="${SERVICE_URL}/health"
  --http-method=GET
  --attempt-deadline=60s
  --description="Keeps ${SERVICE} awake so Claude's connector doesn't time out on a cold start. See deploy/cloudrun/README.md."
)
if gcloud scheduler jobs describe "$KEEPWARM_JOB" --location="$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$KEEPWARM_JOB" "${keepwarm_flags[@]}" >/dev/null
else
  gcloud scheduler jobs create http "$KEEPWARM_JOB" "${keepwarm_flags[@]}" >/dev/null
fi

say "Setup complete. Next: bash deploy/cloudrun/deploy.sh"
