#!/usr/bin/env bash
# Build this repo with Cloud Build and deploy it to Cloud Run.
# Run from Cloud Shell after setup.sh:  bash deploy/cloudrun/deploy.sh
# Re-run any time to ship code, env.yaml or config.sh changes.
# Note: this re-applies every setting below, undoing manual console edits to the service.

set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
REPO_ROOT="$(cd ../.. && pwd)"

# Every disabled tool must have a row explaining it in README.md ("Tools turned off").
disabled_tools="$(sed -n 's/^WORKSPACE_MCP_DISABLED_TOOLS: "\(.*\)"$/\1/p' env.yaml)"
for tool in ${disabled_tools//,/ }; do
  if ! grep -q "| \`${tool}\` |" README.md; then
    echo "README.md has no 'Tools turned off' row for ${tool}. Add one, then re-run." >&2
    exit 1
  fi
done

# Server env = env.yaml (behavior) + identifiers from config.sh.
# gcloud can't combine --env-vars-file with --set-env-vars, so build one file.
env_file="$(mktemp)"
trap 'rm -f "$env_file"' EXIT
cat env.yaml >"$env_file"
cat >>"$env_file" <<YAML
WORKSPACE_EXTERNAL_URL: "${SERVICE_URL}"
GOOGLE_OAUTH_CLIENT_ID: "${GOOGLE_OAUTH_CLIENT_ID}"
WORKSPACE_MCP_OAUTH_PROXY_DISK_DIRECTORY: "${SESSIONS_MOUNT}"
WORKSPACE_MCP_FILES_GCS_BUCKET: "${FILES_BUCKET}"
YAML

gcloud config set project "$PROJECT_ID" >/dev/null

volume_flags=(
  --add-volume="name=sessions,type=cloud-storage,bucket=${SESSIONS_BUCKET},mount-path=${SESSIONS_MOUNT},mount-options=uid=${APP_UID};gid=${APP_GID};file-mode=600;dir-mode=700"
)
# On updates, replace the volume definition instead of adding a duplicate.
if gcloud run services describe "$SERVICE" --region="$REGION" >/dev/null 2>&1; then
  volume_flags=(--clear-volumes --clear-volume-mounts "${volume_flags[@]}")
fi

# max-instances=1 keeps a single writer for the file-based session store.
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
  --env-vars-file="$env_file" \
  --set-secrets="GOOGLE_OAUTH_CLIENT_SECRET=${CLIENT_SECRET_NAME}:latest,FASTMCP_SERVER_AUTH_GOOGLE_JWT_SIGNING_KEY=${JWT_SECRET_NAME}:latest"

echo
echo "Deployed. MCP endpoint (Claude connector URL): ${SERVICE_URL}/mcp"
curl -fsS "${SERVICE_URL}/health" && echo
