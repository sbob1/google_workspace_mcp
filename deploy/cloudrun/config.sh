# Shared settings for the Seanbob Ventures Cloud Run deployment.
# Sourced by setup.sh and deploy.sh. No secrets live here.

PROJECT_ID="seanbob-ventures"
PROJECT_NUMBER="459981624154"
REGION="us-central1"
SERVICE="workspace-mcp"
SERVICE_URL="https://${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"

# Service accounts
RUN_SA_NAME="workspace-mcp-run"      # identity the server runs as
BUILD_SA_NAME="workspace-mcp-build"  # identity Cloud Build uses to build the image
RUN_SA="${RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUILD_SA="${BUILD_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Buckets
SESSIONS_BUCKET="seanbob-ventures-mcp-sessions"  # OAuth proxy store (Fernet-encrypted files)
FILES_BUCKET="seanbob-ventures-mcp-files"        # short-lived download staging

# Secret Manager secret names (values are never stored in this repo)
CLIENT_SECRET_NAME="workspace-mcp-client-secret"
JWT_SECRET_NAME="workspace-mcp-jwt-key"

# Container user in the Dockerfile ("app") — owns files on the sessions mount
APP_UID="1000"
APP_GID="1000"
