# Decisions — Seanbob Ventures Workspace MCP

Why the deployment is the way it is. **This is history, not configuration:** current values live
where `README.md` → "Where values live" says. When a decision changes, add a new entry and mark
the old one **Superseded by D#** — don't rewrite history. Open work lives in Linear, not here.

Owner: Sean. Format: date · decision · why · rejected alternatives · status.

---

### D1 · 2026-10-12 · Self-host the open-source Workspace MCP server
- **Decision:** fork taylorwilsdon/google_workspace_mcp and run it ourselves as one Claude
  connector for every Workspace app.
- **Why:** Sean wants Claude to act on the whole Workspace with no split across connectors.
  The REST APIs cover everything; this server exposes them as one MCP connector, on our own OAuth
  client, with our own tokens.
- **Rejected:** Google's Workspace MCP servers (Gmail has no send/trash, Drive no share/update);
  Claude's built-in connectors (subset only); workspacemcp.com hosted plan (a third party holds
  the tokens); building our own server (weeks of work for parity).
- **Status:** Active.

### D2 · 2026-10-12 · Host on Cloud Run in a general Seanbob Ventures project
- **Decision:** Google Cloud Run, in project `seanbob-ventures` (org seanbobventures.com).
- **Why:** server, OAuth client, secrets, tokens, logs and billing in one place Sean owns;
  near-zero cost when idle. The project is meant to house everything Seanbob Ventures builds for
  itself, not just this server. The display name was later changed (current name: README →
  Console-only settings); the ID is permanent and renaming it would mean rebuilding everything.
- **Rejected:** Railway (simpler deploys, but a third party holds the tokens); Mac mini + tunnel
  (only up when the Mac is). First-choice ID `sbv-agents` was taken globally.
- **Status:** Active.

### D3 · 2026-10-12 · One agentic Web OAuth client behind an Internal consent screen
- **Decision:** a single Web-application OAuth client marked "Use this client for an AI-powered
  agent", used by Claude chat and Claude Code; consent screen audience Internal.
- **Why:** Google requires agent clients to be marked agentic (Oct 12–Nov 11, 2026 window;
  permanent from Nov 12). Internal limits sign-in to seanbobventures.com accounts — the server
  has no domain allowlist of its own. One hosted URL serves every client, so a second (Desktop)
  client isn't needed.
- **Rejected:** separate Desktop client for Claude Code (dropped after reading the server docs);
  External consent screen in testing mode (sign-ins expire every 7 days).
- **Status:** Active.

### D4 · 2026-10-12 · Stateless OAuth 2.1, session store on a Cloud Storage mount
- **Decision:** OAuth 2.1 + stateless mode; FastMCP's encrypted `disk` session store on a Cloud
  Storage FUSE mount; one instance max (single writer).
- **Why:** the service can scale to zero and sign-ins still survive restarts, at ~$0.
- **Rejected:** in-memory store + always-on instance (~$12/month, reconnect after every update);
  Valkey (~$22/month). Not covered by upstream docs — accepted with a single-writer constraint.
- **Status:** Active. Verified 2026-10-13: sign-in survived an overnight scale-to-zero.

### D5 · 2026-10-12 · Full tool tier with specific tools turned off
- **Decision:** tier `complete`; turn off the tools that let an agent share data out or run code.
  The current list and per-tool reasons live in `README.md` → "Tools turned off".
- **Why:** Sean wants everything, but emails and docs can carry prompt injection; these tools are
  the main exfiltration and code-execution paths. Gmail filters stay on (the server can't add
  forwarding addresses). No permanent Gmail delete: the server never requests the
  `mail.google.com` scope.
- **History:** launched with Drive sharing and Apps Script run/deploy off; the 2026-10-12 review
  added Apps Script triggers and the unconfigured search tools.
- **Status:** Active. Easy to change (`env.yaml`, no reconnect).

### D6 · 2026-10-12 · Patch Apps Script project delete to trash-only
- **Decision:** fork change — only delete Apps Script files, and move them to Drive trash.
- **Why:** independent review found upstream permanently deleted any Drive file ID passed to it.
- **Status:** Active. Candidate to contribute upstream.

### D7 · 2026-10-12 · Sign-ins expire after 90 days
- **Decision:** shorten the session refresh-token lifetime from upstream's 1 year.
- **Why:** limits how long a leaked session stays useful; reconnecting quarterly is cheap.
- **Status:** Active.

### D8 · 2026-10-12 · Cost guard: spend cap + alert, no Cloudflare yet
- **Decision:** scale to zero, one instance max, a Cloud Run spend cap and a billing-account alert.
- **Why:** bounds the cost of abuse (unauthenticated requests are rejected but still billed) at
  ~$0 normal cost. Trade-off: hitting the cap pauses the connector until it's lifted.
- **Rejected for now:** Cloudflare in front with rate limiting — revisit if the alerts ever fire.
- **Status:** Active.

### D9 · 2026-10-13 · Keep-awake ping
- **Decision:** a Cloud Scheduler job pings `/health` often enough that the instance stays warm.
- **Why:** after idling, the first connection could take long enough that Claude showed the
  connector as disconnected (seen 2026-10-13 morning). Stays within free tiers.
- **Rejected:** always-on instance (~$13/month; keep as the fallback); having Claude wake the
  server first (not possible — the connector loads before Claude can act).
- **Status:** Active.

### D10 · 2026-10-13 · Documentation structure
- **Decision:** `README.md` = how it works now; `DECISIONS.md` = why; root `AGENTS.md` = guide for
  AI agents; open work in Linear. Each fact has one home.
- **Why:** Sean's one-source-of-truth rule; keeps the README short as history accumulates.
- **Status:** Active.

### D11 · 2026-10-13 · Weekly Claude-reviewed upstream sync
- **Decision:** a weekly Claude scheduled task prepares upstream updates on a branch, reviews
  them for security, and files a Linear issue; Sean merges and deploys.
- **Why:** upstream ships several releases a week; this server holds broad Google access, so
  updates should arrive regularly but only after a check of new tools, scopes, outbound hosts,
  auth changes and dependencies. Nothing merges or deploys without Sean.
- **Rejected:** GitHub Action that only opens a pull request (no security review; enabling Actions
  in the fork would also activate upstream's publishing workflows); manual reminders (easy to
  skip, all review on Sean); auto-merge or auto-deploy (no human check on a high-access server).
- **Status:** Active. The task writes to Linear under Sean's account (approved exception to How
  We Work → Identity until a "Sean's Agent" Linear connector exists).
