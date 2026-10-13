# Identifiers for the Seanbob Ventures Cloud Run deployment.
# Single source for every name/ID below; setup.sh and deploy.sh read them,
# and deploy.sh passes the derived values to the server. No secrets live here.

PROJECT_ID="seanbob-ventures"
PROJECT_NUMBER="459981624154"
REGION="us-central1"
SERVICE="workspace-mcp"
SERVICE_URL="https://${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"  # Cloud Run deterministic URL

# OAuth client "Claude Workspace MCP" (its secret lives in Secret Manager, see below)
GOOGLE_OAUTH_CLIENT_ID="459981624154-d5rvn4prcqcc7ttqaq6d73tduqll2qb3.apps.googleusercontent.com"

# Service accounts
RUN_SA_NAME="workspace-mcp-run"      # identity the server runs as
BUILD_SA_NAME="workspace-mcp-build"  # identity Cloud Build uses to build the image
RUN_SA="${RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUILD_SA="${BUILD_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Buckets
SESSIONS_BUCKET="seanbob-ventures-mcp-sessions"  # sign-in session store (Fernet-encrypted files)
SESSIONS_MOUNT="/data/oauth-proxy"               # where that bucket is mounted in the container
FILES_BUCKET="seanbob-ventures-mcp-files"        # short-lived download staging

# Secret Manager secret names (values are never stored in this repo)
CLIENT_SECRET_NAME="workspace-mcp-client-secret"
JWT_SECRET_NAME="workspace-mcp-jwt-key"  # also the storage encryption key: rotating it signs everyone out

# Keep-awake ping: Cloud Scheduler job that GETs /health so the server isn't asleep
# when Claude connects. Cloud Run keeps an idle instance ~15 min, so ping more often than that.
KEEPWARM_JOB="workspace-mcp-keepwarm"
KEEPWARM_SCHEDULE="*/5 * * * *"  # cron, UTC

# UID/GID of the Dockerfile's "app" user; owns files on the sessions mount.
# Must equal `id -u app` / `id -g app` in the image — re-check after each upstream sync.
APP_UID="1000"
APP_GID="1000"
