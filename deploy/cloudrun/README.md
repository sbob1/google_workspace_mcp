# Seanbob Ventures — Workspace MCP on Cloud Run

Gives Claude (chat on web/desktop/mobile, and Claude Code) one connector with action access to
the seanbobventures.com Google Workspace: Gmail, Drive, Docs, Sheets, Slides, Calendar, Forms,
Tasks, Contacts, Chat, and Apps Script editing.

**This file is the single source for *why* the deployment is set up this way and for settings
that exist only in the Google Cloud console.** Values used by the scripts live in the files
below; this README names them instead of repeating them. Follows
<https://workspacemcp.com/docs/deployment> unless a section says otherwise.

## Where values live

| What | Source |
|---|---|
| Project, region, service name and URL, OAuth client ID, service accounts, buckets, mount path, secret names, keep-awake job name and schedule | `config.sh` |
| Server behavior (auth mode, tool tier, disabled tools, redirect allowlist, token lifetime) | `env.yaml` |
| Cloud Run sizing and flags (instances, CPU, memory, timeout, volume) | `deploy.sh` |
| APIs, IAM grants, buckets, JWT key creation, keep-awake ping job | `setup.sh` |
| Secret values | Secret Manager (names in `config.sh`) |
| Billing account, trial end date, Bitwarden item for the client-secret JSON | Life OS hub doc ("Seanbob Ventures README" in Drive) |

## Console-only settings (source of truth)

Not scripted — record changes here.

- **Project display name:** SBV Workspace MCP (ID in `config.sh` is permanent).
- **OAuth consent screen:** app name "Seanbob Ventures Workspace Agent"; audience **Internal**
  (only seanbobventures.com accounts can sign in — the server itself has no domain allowlist);
  support and developer contact sean@seanbobventures.com; no scopes declared.
- **OAuth client:** "Claude Workspace MCP"; type Web application; **"Use this client for an
  AI-powered agent" on** (Google's agentic setting — permanent after Nov 12, 2026; changing it
  means a new client); authorized redirect URI = `SERVICE_URL` + `/oauth2callback`.
- **Budgets** (Billing → Budgets & caps):
  - "Cloud Run cap - Seanbob Ventures": **$4/month spend cap** on Cloud Run in this project;
    pauses the service until the 1st or until lifted.
  - "Project alert - Seanbob Ventures": **$5/month alert** on the whole billing account,
    gross of credits; emails at 50/90/100%.
- **Claude connector:** "Seanbob Workspace", URL = `SERVICE_URL` + `/mcp`, no advanced
  settings (Claude registers itself). Claude's built-in Gmail and Google Drive connectors are
  separate and not governed by this deployment's tool settings.

## Design choices

- **OAuth 2.1 + stateless mode:** per-user bearer tokens, no local file writes, no long-lived
  HTTP sessions — so the service can scale to zero.
- **Sign-in session store:** FastMCP's `disk` backend (Fernet-encrypted files, key derived from
  the JWT secret) on a Cloud Storage FUSE mount, so sign-ins survive restarts without paying for
  Valkey. *Not covered by the upstream docs.* Relies on a single writer: `deploy.sh` caps the
  service at one instance (old and new revisions can briefly overlap during a deploy). The store
  never prunes expired entries; volume is tiny.
- **Session lifetime:** shortened from upstream's 1-year default; Claude must reconnect when
  `WORKSPACE_MCP_OAUTH_PROXY_REFRESH_TOKEN_EXPIRY_SECONDS` (`env.yaml`) elapses after sign-in.
- **Client registration allowlist:** Claude's web callbacks plus any `localhost`/`127.0.0.1`
  callback (needed for Claude Code, but it admits any local client). The Internal consent
  screen is the real gate.
- **No credential-store bucket or CMEK:** stateless mode doesn't use the credential store.
- **Downloads:** staged in the files bucket and handed out as signed URLs; a lifecycle rule in
  `setup.sh` deletes old objects.
- **Keep-awake ping (added Oct 13, 2026):** a Cloud Scheduler job (`KEEPWARM_JOB` in
  `config.sh`, created by `setup.sh`) GETs `/health` on `KEEPWARM_SCHEDULE`. Without it the
  service scales to zero when idle, and the first connection afterward can take long enough that
  Claude shows the connector as disconnected. Pings are tiny and idle instances aren't billed, so
  this stays in free tiers (3 free Scheduler jobs per billing account). Google can still restart
  the instance occasionally. Alternative if that's not enough: `--min-instances=1` in `deploy.sh`
  (~$13/month; raise the Cloud Run cap first).
- **Cost guard:** scale to zero + one instance + the budgets above. Expected cost ≈ $0/month.

## Tools turned off

Listed in `env.yaml` (`WORKSPACE_MCP_DISABLED_TOOLS`); `deploy.sh` refuses to run if a listed
tool has no row here. Decided Oct 2026: these are the main ways a malicious email or doc could
steer an agent into leaking data or running code.

| Tool | What it does | Why it's off |
|---|---|---|
| `manage_drive_access` | Grant/update/revoke sharing; transfer ownership | Could share files outside the domain |
| `set_drive_file_permissions` | Change link sharing ("anyone with the link") | Could make files public |
| `run_script_function` | Run a function in a deployed Apps Script, as Sean | Code runs with full access, bypassing other limits |
| `manage_deployment` | Create/update/delete Apps Script deployments | Publishes code for the tools above to run |
| `manage_script_trigger` | List/delete triggers; executes script code to do so | Runs the latest saved (editable) script code |
| `search_custom` | Google Programmable Search | Not configured (no search engine keys) |
| `get_search_engine_info` | Programmable Search metadata | Not configured |

Still on, deliberately: Apps Script editing (note: edited code also runs on any triggers Sean
already set up), Gmail send and filters (the server can't add forwarding addresses), Chat send,
Calendar invites, Forms publish settings. Keep Claude's approval prompts on for actions that send
or publish.

**To turn a tool back on:** remove it from `env.yaml` and run `deploy.sh`. No reconnect needed —
Google access is granted per service, so turning a tool off doesn't remove its OAuth scope.

## Fork changes vs upstream

Keep these when syncing from taylorwilsdon/google_workspace_mcp:

- `deploy/cloudrun/` (this folder).
- `Dockerfile`: adds the `gcs` extra.
- `gappsscript/apps_script_tools.py` `_delete_script_project_impl`: only acts on Apps Script
  files and moves them to Drive trash. Upstream permanently deletes any Drive file ID.
  Test: `tests/gappsscript/test_apps_script_tools.py`. Candidate to contribute upstream.

## First-time setup

In the console: consent screen, OAuth client, and its secret (see Console-only settings). Then
in Cloud Shell:

```bash
git clone https://github.com/sbob1/google_workspace_mcp.git && cd google_workspace_mcp
bash deploy/cloudrun/setup.sh && bash deploy/cloudrun/deploy.sh
```

Add the Claude connector with the URL `deploy.sh` prints. For Claude Code:
`claude mcp add --transport http seanbob-workspace <that URL>`.

## Changing things

Edit the file that holds the value (table above), then run `deploy.sh`. Upstream update: GitHub
"Sync fork", review the diff (keep the fork changes above, re-check `APP_UID`), run `deploy.sh`.

## Verify

`deploy.sh` prints `/health`. Confirmed at launch: an unauthenticated `POST /mcp` returns 401;
registering a client with a non-allowlisted redirect returns 400. Confirmed Oct 13, 2026: sign-in
survived an overnight scale-to-zero (no reconnect needed). Keep-awake ping: Cloud Scheduler →
`KEEPWARM_JOB` shows a recent successful run.

## Off switches

- **Cut Claude's access now:** myaccount.google.com → Security → third-party access → remove
  "Seanbob Ventures Workspace Agent", and delete the objects in the sessions bucket.
- **Stop the server:** delete the Cloud Run service (setting max instances to 0 in the console
  is undone by the next `deploy.sh`). Also pause or delete the keep-awake job (Cloud Scheduler →
  `KEEPWARM_JOB`), or it keeps pinging; re-running `setup.sh` recreates it.
