# Seanbob Ventures — Workspace MCP on Cloud Run

Gives Claude (chat on web/desktop/mobile, and Claude Code) one connector with action access to
the seanbobventures.com Google Workspace: Gmail, Drive, Docs, Sheets, Slides, Calendar, Forms,
Tasks, Contacts, Chat, and Apps Script editing.

**This file describes the deployment as it is now.** Why it's built this way: `DECISIONS.md`.
Open work: Linear (team Seanbob Ventures, label Ventures HQ). Values used by the scripts live in
the files below; this README names them instead of repeating them. Follows
<https://workspacemcp.com/docs/deployment> unless `DECISIONS.md` says otherwise.

## Where values live

| What | Source |
|---|---|
| Project, region, service name and URL, OAuth client ID, service accounts, buckets, mount path, secret names, keep-awake job name and schedule | `config.sh` |
| Server behavior (auth mode, tool tier, disabled tools, redirect allowlist, token lifetime) | `env.yaml` |
| Cloud Run sizing and flags (instances, CPU, memory, timeout, volume) | `deploy.sh` |
| APIs, IAM grants, buckets, JWT key creation, keep-awake ping job | `setup.sh` |
| Secret values | Secret Manager (names in `config.sh`) |
| Settings that exist only in the Google Cloud console or Claude | "Console-only settings" below |
| Billing account, trial end date, Bitwarden item for the client-secret JSON | Life OS hub doc ("Seanbob Ventures README" in Drive) |

## Console-only settings

Not scripted — this list is their source of truth; update it when the console changes.

- **Project display name:** SBV Workspace MCP (the ID in `config.sh` is permanent).
- **OAuth consent screen:** app name "Seanbob Ventures Workspace Agent"; audience **Internal**
  (the only domain gate); support and developer contact sean@seanbobventures.com; no scopes declared.
- **OAuth client:** "Claude Workspace MCP"; Web application; **"Use this client for an AI-powered
  agent" on** (can't be changed after Nov 12, 2026 — changing it means a new client); authorized
  redirect URI = `SERVICE_URL` + `/oauth2callback`.
- **Budgets** (Billing → Budgets & caps):
  - "Cloud Run cap - Seanbob Ventures": $4/month spend cap on Cloud Run in this project; pauses
    the service until the 1st or until lifted.
  - "Project alert - Seanbob Ventures": $5/month alert on the whole billing account, gross of
    credits; emails at 50/90/100%.
- **Claude connector:** "Seanbob Workspace", URL = `SERVICE_URL` + `/mcp`, no advanced settings.
  Claude's built-in Gmail and Google Drive connectors are separate and not governed by this
  deployment's tool settings.
- **Claude scheduled task:** "Weekly upstream sync review — Workspace MCP", Mondays 6:50 AM
  Mountain, runs in the cloud with automatic approval. Its instructions live in the task itself
  (Claude → scheduled tasks); see "Changing things" for what it does.

## How it works

- **Auth:** OAuth 2.1, stateless mode; each sign-in lasts the refresh-token lifetime in `env.yaml`
  (D3, D4, D7).
- **Sign-in session store:** encrypted files in the sessions bucket, mounted into the container.
  Requires a single writer: keep max instances at 1 (D4). The encryption key is the JWT secret —
  rotating it signs everyone out.
- **Client registration:** only Claude's web callbacks and local (`localhost`/`127.0.0.1`)
  callbacks for Claude Code may register (D3).
- **Downloads:** staged in the files bucket as signed URLs; a lifecycle rule deletes old objects.
- **Keep-awake ping:** a Cloud Scheduler job GETs `/health` so the server is awake when Claude
  connects (D9).
- **Cost:** scale to zero, one instance, and the budgets above; expected ≈ $0/month (D8).

## Tools turned off

Listed in `env.yaml` (`WORKSPACE_MCP_DISABLED_TOOLS`); `deploy.sh` refuses to run if a listed
tool has no row here. Background: D5.

| Tool | What it does | Why it's off |
|---|---|---|
| `manage_drive_access` | Grant/update/revoke sharing; transfer ownership | Could share files outside the domain |
| `set_drive_file_permissions` | Change link sharing ("anyone with the link") | Could make files public |
| `run_script_function` | Run a function in a deployed Apps Script, as Sean | Code runs with full access, bypassing other limits |
| `manage_deployment` | Create/update/delete Apps Script deployments | Publishes code for the tools above to run |
| `manage_script_trigger` | List/delete triggers; executes script code to do so | Runs the latest saved (editable) script code |
| `search_custom` | Google Programmable Search | Not configured (no search engine keys) |
| `get_search_engine_info` | Programmable Search metadata | Not configured |

Still on, deliberately: Apps Script editing (edited code also runs on any triggers Sean already
set up), Gmail send and filters, Chat send, Calendar invites, Forms publish settings. Keep Claude's
approval prompts on for actions that send or publish.

**To turn a tool back on:** remove it from `env.yaml` and run `deploy.sh`. No reconnect needed —
Google access is granted per service, so turning a tool off doesn't remove its OAuth scope.

## Fork changes vs upstream

Keep these when syncing from taylorwilsdon/google_workspace_mcp; everything else should match
upstream:

- `AGENTS.md` (repo root) and `deploy/cloudrun/` (this folder).
- `Dockerfile`: adds the `gcs` extra.
- `gappsscript/apps_script_tools.py` `_delete_script_project_impl`: Apps Script files only, moved
  to Drive trash (D6). Test: `tests/gappsscript/test_apps_script_tools.py`.

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

Edit the file that holds the value (table above), then in Cloud Shell:
`cd ~/google_workspace_mcp && git pull && bash deploy/cloudrun/setup.sh && bash deploy/cloudrun/deploy.sh`
(both scripts are safe to re-run). If a change reflects a new decision, add it to `DECISIONS.md`.

**Upstream updates (D11):** the weekly scheduled task merges upstream into a `sync/upstream-<date>`
branch, keeps the fork changes, runs the checks, reviews the diff for security, and files a
"Review upstream sync" issue in Linear (Triage) with the verdict and a compare link. It never
merges to main or deploys. Sean approves by merging that branch, then running the command above.
Manual fallback: GitHub "Sync fork", review the diff, keep the fork changes, re-check `APP_UID`,
then run the command above.

## Verify

- `deploy.sh` ends by printing `/health`.
- An unauthenticated `POST /mcp` returns 401; registering a client with a non-allowlisted
  redirect returns 400.
- Claude doesn't ask to reconnect after a redeploy or an idle night.
- Cloud Scheduler → `KEEPWARM_JOB` shows recent successful runs.

## Off switches

- **Cut Claude's access now:** myaccount.google.com → Security → third-party access → remove
  "Seanbob Ventures Workspace Agent", and delete the objects in the sessions bucket.
- **Stop the server:** delete the Cloud Run service (max instances 0 in the console is undone by
  the next `deploy.sh`), and pause or delete the keep-awake job — re-running `setup.sh` recreates it.
