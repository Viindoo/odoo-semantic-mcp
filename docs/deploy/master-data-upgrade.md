# Profiles and Repos — Admin Setup Guide

> **Note (2026-05-20):** The automatic master-data seed roster (previously
> 26 profiles + 48 repos seeded by `migrate`) has been removed for the
> public release. Profiles and repos are now created by admins via the
> web UI or the JSON API. The profile hierarchy mechanism (ADR-0016) is
> unchanged.

## Creating Profiles via the Web UI

Log in as admin → **Settings → Profiles → New Profile**.

Fill in:

| Field | Description |
|---|---|
| **Name** | Short identifier, e.g. `odoo_17`, `mycompany_addons_17` |
| **Odoo version** | e.g. `17.0` |
| **Description** | Optional human-readable label |
| **Parent profile** | Optional. Set to build a delta hierarchy (ADR-0016). |

Save → the profile appears in the list immediately.

## Adding Repos to a Profile

Settings → Profiles → select profile → **Repos** tab → **Add Repo**.

| Field | Description |
|---|---|
| **URL** | Git URL (HTTPS or SSH). SSH repos require a registered key (Settings → SSH Keys). |
| **Branch** | e.g. `17.0` |
| **Local path** | Auto-filled from default clone dir; override if needed |

`UNIQUE (url, branch)` is enforced — each repo can belong to only one profile.

## Creating Profiles via the JSON API

```bash
curl -X POST https://<your-host>/api/profiles \
  -H "X-API-Key: <admin-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"name": "myprofile_17", "odoo_version": "17.0", "description": "My addons v17"}'
```

Add a repo:

```bash
curl -X POST https://<your-host>/api/profiles/myprofile_17/repos \
  -H "X-API-Key: <admin-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com/<org>/<repo>.git", "branch": "17.0"}'
```

## Profile Delta Hierarchy (ADR-0016)

The system supports parent→child profiles where child inherits all repos from
ancestor profiles automatically at query time. A typical three-tier setup:

```
odoo_N              (Odoo CE base repo)
  └─ <your-standard-profile>_N   (CE + your public addons)
       └─ <your-internal-profile>_N  (CE + public + internal repos)
```

Set `parent_profile_id` via the web UI (Profile edit → Parent field) or via the
API. Rules enforced server-side:

- **Cycle-free**: cannot set a descendant as a parent.
- **Version-match**: parent and child must share the same `odoo_version`.

When indexing, always index from root to leaf:
`index odoo_N` → `index <your-standard-profile>_N` → `index <your-internal-profile>_N`.

## Upgrading an Existing Deployment

If upgrading from a version that had the old seed roster:

1. **Stop services** (optional but recommended for zero-write window):
   ```bash
   sudo systemctl stop odoo-semantic-mcp odoo-semantic-webui
   ```

2. **Backup PostgreSQL** (required):
   ```bash
   pg_dump $PG_DSN > backup_pre_upgrade_$(date +%F).sql
   ```

3. **Pull and migrate**:
   ```bash
   cd /opt/odoo-semantic-mcp
   sudo -u odoo-semantic git pull
   sudo -u odoo-semantic -H bash -c '
       export ODOO_SEMANTIC_CONF=/etc/odoo-semantic/odoo-semantic.conf
       ~/.venv/odoo-semantic-mcp/bin/python -m src.db.migrate
   '
   ```
   `migrate` is idempotent — safe to run multiple times.

4. **Restart services**:
   ```bash
   sudo systemctl start odoo-semantic-mcp odoo-semantic-webui
   ```

5. **Create your profiles** via the web UI or API as described above.

## Rollback

Restore from the pre-upgrade backup:

```bash
sudo -u postgres psql odoo_semantic_db < backup_pre_upgrade_$(date +%F).sql
```

---

Back to [`docs/deploy.md`](../deploy.md) for the full deployment guide.
