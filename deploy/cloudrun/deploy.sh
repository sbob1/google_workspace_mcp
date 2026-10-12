#!/usr/bin/env bash
# Build this repo with Cloud Build and deploy it to Cloud Run.
# Run from Cloud Shell after setup.sh:  bash deploy/cloudrun/deploy.sh
# Re-run any time to ship code or env.yaml changes.

set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
REPO_ROOT="$(cd ../.. && pwd)"

gcloud config set project "$PROJECT_ID" >/dev/null

volume_flags=(
  --add-volume="name=sessions,type=cloud-storage,bucket=${SESSIONS_BUCKET},mount-path=/data/oauth-proxy,mount-options=uid=${APP_UID};gid=${APP_GID};file-mode=600;dir-mode=700"
)
# On updates, replace the volume definition instead of adding a duplicate.
if gcloud run services describe "$SERVICE" --region="$REGION" >/dev/null 2>&1; then
  volume_flags=(--clear-volumes --clear-volume-mounts "${volume_flags[@]}")
fi

gcloud run deploy "$SERVICE" \
  --source="$REPO_ROOT" \
  --region="$REGION" \
  --service-account="$RUN_SA" \
  --build-service-account="projects/${PROJECT_ID}/serviceAccounts/${BUILD_SA}" \
  --no-invoker-iam-check \
  --ingress=all \
  --execution-environment=gen2 \
  --min-instances=0 \
  --max-instances=1 \
  --cpu=1 \
  --memory=1Gi \
  --timeout=300 \
  "${volume_flags[@]}" \
  --env-vars-file=./env.yaml \
  --set-secrets="GOOGLE_OAUTH_CLIENT_SECRET=${CLIENT_SECRET_NAME}:latest,FASTMCP_SERVER_AUTH_GOOGLE_JWT_SIGNING_KEY=${JWT_SECRET_NAME}:latest"

echo
echo "Deployed. MCP endpoint: ${SERVICE_URL}/mcp"
curl -fsS "${SERVICE_URL}/health" && echo
