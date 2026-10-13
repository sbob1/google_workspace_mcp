# Agent guide — Seanbob Ventures fork

Sean's fork of taylorwilsdon/google_workspace_mcp, deployed to Google Cloud Run as the
"Seanbob Workspace" Claude connector for the seanbobventures.com Google Workspace.

- **Start here:** `deploy/cloudrun/README.md` (how the deployment works now and where every value
  lives), then `deploy/cloudrun/DECISIONS.md` (why).
- **One home per fact.** Change a value in the file the README names; never copy it elsewhere.
  New or changed decision → new `DECISIONS.md` entry; mark the old one superseded.
- **Stay close to upstream.** Fork changes are listed in README → "Fork changes vs upstream".
  Keep new ones small, list them there, and add tests.
- **Turned-off tools** are listed in `deploy/cloudrun/env.yaml`; each needs a README row
  (`deploy.sh` enforces it).
- **Never commit secrets.** Secret values live only in Google Secret Manager.
- **Approval first** (per Sean's Linear "How We Work"): pushing to main, deploying, Google Cloud
  console changes, spending money, deleting data. Sean runs `setup.sh`/`deploy.sh` in Cloud Shell.
- **Open work** is tracked in Linear (team Seanbob Ventures, labels Ventures HQ + Operations),
  not in these docs.
- **Checks:** `uv run --frozen pytest tests/<area>` and
  `uv run --frozen --extra dev ruff check <files>`; `shellcheck -x` from `deploy/cloudrun/` for the
  scripts.
