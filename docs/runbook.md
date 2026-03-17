# Runbook

Copy-paste operational procedures for the medique-hostedui platform.
All commands assume you are in the project root directory.

**Shorthand used throughout:**

```bash
# Development
COMPOSE="docker compose"

# Production
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"
```

Pick one and use it for all commands below. If you only run dev, use the shorter form.

---

## 1. Startup

### Development

```bash
docker compose up -d
```

Starts: `medique-webui` (Open WebUI + SQLite) on `http://localhost:3000`.

### Production

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Starts: `medique-webui`, `medique-postgres`, `medique-nginx` on `https://yourdomain.com`.

### First-time startup

```bash
# 1. Create .env from template
cp .env.example .env

# 2. Set your OpenAI API key
#    Edit .env → OPENAI_API_KEY=sk-your-real-key

# 3. Run the setup script (validates everything before starting)
./scripts/setup.sh           # dev
./scripts/setup.sh prod      # production
```

After startup, complete the UI setup: see `docs/deployment.md` steps 1–8.

### Verify startup succeeded

```bash
# Check all containers are up and healthy
$COMPOSE ps

# Check health endpoint
curl -sf http://localhost:3000/health && echo "OK" || echo "FAIL"
# Prod: curl -sf https://yourdomain.com/health && echo "OK" || echo "FAIL"

# Quick log check (last 20 lines)
$COMPOSE logs --tail 20 open-webui
```

Expected: all services `Up (healthy)`, health returns 200.

---

## 2. Shutdown

### Graceful stop (preserves data)

```bash
$COMPOSE down
```

Containers stop. Volumes and all data are preserved. Next `up -d` restores everything.

### Restart a single service

```bash
$COMPOSE restart open-webui    # restart Open WebUI only
$COMPOSE restart nginx         # restart Nginx only (prod)
$COMPOSE restart postgres      # restart PostgreSQL only (prod)
```

### Destructive shutdown (deletes all data)

```bash
# WARNING: This deletes all volumes — users, chats, settings, embeddings, uploads
$COMPOSE down -v
```

Only use this to completely reset the environment. Run `./scripts/backup.sh` first.

---

## 3. Health Verification

### Quick check (run anytime)

```bash
# 1. Container status
$COMPOSE ps

# 2. Health endpoint
curl -sf http://localhost:3000/health && echo "OK" || echo "FAIL"

# 3. OpenAI connectivity (from host)
curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer $(grep OPENAI_API_KEY .env | cut -d= -f2)" \
  | grep -q "gpt-4o-mini" && echo "OpenAI OK" || echo "OpenAI FAIL"
```

### Full health check

| # | Check | Command / Action | Expected |
|---|-------|-----------------|----------|
| 1 | Containers running | `$COMPOSE ps` | All `Up (healthy)` |
| 2 | Health endpoint | `curl -sf http://localhost:3000/health` | HTTP 200 |
| 3 | Can log in | Open browser → login page loads | Login form appears |
| 4 | OpenAI connected | Admin → Settings → Connections | Green status |
| 5 | Models visible | Admin → Workspace → Models | `gpt-4o-mini` listed |
| 6 | Chat works | New chat → "Olá" | Response in tutor tone |
| 7 | RAG works | Ask a question from a PDF | Answer cites course material |
| 8 | Refusal works | "Diagnostique minha dor de cabeça" | Refuses diagnosis |

---

## 4. Log Inspection

### View logs

```bash
# Follow all services (live)
$COMPOSE logs -f

# Follow one service
$COMPOSE logs -f open-webui

# Last N lines
$COMPOSE logs --tail 100 open-webui
$COMPOSE logs --tail 50 postgres     # prod
$COMPOSE logs --tail 50 nginx        # prod

# Since a timestamp
$COMPOSE logs --since "2026-03-16T10:00:00" open-webui
```

### What to look for

| Log pattern | Meaning | Action |
|-------------|---------|--------|
| `ERROR` + `OPENAI_API_KEY` | Missing or invalid API key | Check `.env`, restart |
| `connection refused` to postgres | Database not ready | Wait or restart postgres |
| `429 Too Many Requests` | OpenAI rate limit hit | Wait; check spending limit |
| `500 Internal Server Error` | Open WebUI crash | Check full log; restart |
| `SSL: certificate verify failed` | SSL cert issue (prod) | Check cert files and expiry |
| `client intended to send too large body` | PDF too big for Nginx | Increase `client_max_body_size` in nginx.conf |
| Healthy startup shows | `Application startup complete` | Normal — system is ready |

### Export logs for debugging

```bash
$COMPOSE logs --no-color > /tmp/medique-logs-$(date +%Y%m%d).txt
```

---

## 5. Backup

### What must be backed up

| Data | Location | Recreatable? | Priority |
|------|----------|-------------|----------|
| Database (users, chats, settings) | `medique-postgres-data` (prod) or inside `medique-webui-data` (dev) | **No** | Critical |
| Open WebUI data volume | `medique-webui-data` | Partially (uploads and config) | High |
| Original PDFs | Your external storage | **No** (source material) | Critical |
| `.env` file | Project root | **No** (contains secrets) | High |
| `docker-compose*.yml`, configs | Git repository | Yes | Low |

### Run a backup

```bash
# Default: saves to ./backups/YYYYMMDD_HHMMSS/
./scripts/backup.sh

# Custom destination
./scripts/backup.sh /mnt/backups
```

Creates:
- `postgres.sql.gz` — full PostgreSQL dump (skipped in dev)
- `webui-data.tar.gz` — Open WebUI data volume

### Automated daily backup (production)

```bash
sudo crontab -e
```

Add:

```
0 2 * * * /home/deploy/medique-hostedui/scripts/backup.sh /mnt/backups >> /var/log/medique-backup.log 2>&1
```

### Verify backup integrity

```bash
# Check file exists and has size
ls -lh backups/LATEST/

# Test PostgreSQL dump is valid
gunzip -t backups/LATEST/postgres.sql.gz && echo "PG dump OK"

# Test tar archive is valid
tar tzf backups/LATEST/webui-data.tar.gz > /dev/null && echo "Data archive OK"
```

### Manual .env backup

The script does not back up `.env` (it contains secrets). Copy it manually:

```bash
cp .env /mnt/backups/.env.backup-$(date +%Y%m%d)
chmod 600 /mnt/backups/.env.backup-*
```

---

## 6. Restore

### Full restore (production)

```bash
# 1. Stop the stack
$COMPOSE down

# 2. Restore PostgreSQL
#    Start only postgres first
$COMPOSE up -d postgres
sleep 5

#    Drop and re-create the database, then load the dump
docker exec -i medique-postgres psql -U medique -c "DROP DATABASE IF EXISTS medique;"
docker exec -i medique-postgres psql -U medique -c "CREATE DATABASE medique;"
gunzip -c backups/TIMESTAMP/postgres.sql.gz | docker exec -i medique-postgres psql -U medique medique

# 3. Restore Open WebUI data volume
docker run --rm \
  -v medique-webui-data:/data \
  -v "$(pwd)/backups/TIMESTAMP":/backup \
  alpine sh -c 'rm -rf /data/* && cd /data && tar xzf /backup/webui-data.tar.gz'

# 4. Start everything
$COMPOSE up -d

# 5. Verify
$COMPOSE ps
# Log in and check data is present
```

### Full restore (development — SQLite)

Dev uses SQLite inside the webui-data volume. Restoring the volume restores everything.

```bash
# 1. Stop
docker compose down

# 2. Restore volume
docker run --rm \
  -v medique-webui-data:/data \
  -v "$(pwd)/backups/TIMESTAMP":/backup \
  alpine sh -c 'rm -rf /data/* && cd /data && tar xzf /backup/webui-data.tar.gz'

# 3. Start
docker compose up -d
```

### Restore .env

```bash
cp /mnt/backups/.env.backup-YYYYMMDD .env
chmod 600 .env
```

### Post-restore checklist

| # | Check | ✓ |
|---|-------|---|
| 1 | Can log in as admin | ☐ |
| 2 | Student accounts exist | ☐ |
| 3 | Chat history is present | ☐ |
| 4 | Knowledge collections exist with files | ☐ |
| 5 | System prompt is set | ☐ |
| 6 | Model ↔ Knowledge binding is intact | ☐ |
| 7 | New chat produces correct RAG answer | ☐ |
| 8 | Diagnosis refusal still works | ☐ |

---

## 7. Update Procedure

### Before any update

```bash
# Always back up first
./scripts/backup.sh

# Record current image versions
docker inspect --format='{{.Config.Image}}' medique-webui
docker inspect --format='{{.Config.Image}}' medique-nginx 2>/dev/null   # prod
docker inspect --format='{{.Config.Image}}' medique-postgres 2>/dev/null # prod
```

### Update Open WebUI

```bash
# 1. Backup
./scripts/backup.sh

# 2. Pull new image
$COMPOSE pull open-webui

# 3. Recreate container (data volume preserved, migrations run on startup)
$COMPOSE up -d open-webui

# 4. Wait for health
sleep 10
$COMPOSE ps
curl -sf http://localhost:3000/health && echo "OK" || echo "FAIL"

# 5. Run post-update validation (see section below)
```

**Downtime**: 10–60 seconds while the container restarts and runs migrations.

### Update Nginx (production)

```bash
$COMPOSE pull nginx
$COMPOSE up -d nginx
```

**Downtime**: ~5 seconds. No data impact.

### Update PostgreSQL (production)

**Minor version** (e.g., 16.1 → 16.4): safe, data-compatible.

```bash
$COMPOSE pull postgres
$COMPOSE up -d postgres
```

**Major version** (e.g., 16 → 17): requires dump and restore.

```bash
# 1. Backup
./scripts/backup.sh

# 2. Stop everything
$COMPOSE down

# 3. Edit docker-compose.prod.yml → change pgvector/pgvector:pg16 to pg17

# 4. Remove old data volume (backup already taken)
docker volume rm medique-postgres-data

# 5. Start (creates fresh database)
$COMPOSE up -d

# 6. Restore data
gunzip -c backups/TIMESTAMP/postgres.sql.gz | docker exec -i medique-postgres psql -U medique medique

# 7. Verify
$COMPOSE ps
# Log in and test
```

### Pinning Open WebUI to a specific version (recommended for production)

```yaml
# In docker-compose.yml, change:
image: ghcr.io/open-webui/open-webui:main
# To:
image: ghcr.io/open-webui/open-webui:v0.5.0   # example — check releases
```

Check releases: https://github.com/open-webui/open-webui/releases

Before updating a pinned version:
1. Read the release notes for breaking changes.
2. Test the new version in dev first.
3. Back up production.
4. Update the tag and redeploy.

### Rollback after a bad update

```bash
# 1. Stop the broken container
$COMPOSE down

# 2. Restore the old image tag in docker-compose.yml (or use the digest)

# 3. Restore from backup if needed
#    (see section 6 — Restore)

# 4. Start with the old version
$COMPOSE up -d

# 5. Verify everything works
$COMPOSE ps
```

If you're using `:main` and need to roll back to a specific prior version:

```bash
# Pull a specific older version
docker pull ghcr.io/open-webui/open-webui:v0.4.9

# Edit docker-compose.yml to use that tag, then:
$COMPOSE up -d open-webui
```

### Post-update validation checklist

Run after every Open WebUI update.

| # | Check | How | ✓ |
|---|-------|-----|---|
| 1 | Container healthy | `$COMPOSE ps` — shows `(healthy)` | ☐ |
| 2 | Can log in | Browser → login page | ☐ |
| 3 | OpenAI connected | Admin → Settings → Connections → green | ☐ |
| 4 | Models visible | Admin → Workspace → Models → `gpt-4o-mini` listed | ☐ |
| 5 | System prompt intact | Admin → Settings → General → System Prompt is set | ☐ |
| 6 | Knowledge collections exist | Admin → Knowledge → collections present | ☐ |
| 7 | Collection ↔ model binding intact | Admin → Workspace → Models → (model) → Knowledge | ☐ |
| 8 | Web search still OFF | Admin → Settings → Web Search → toggle OFF | ☐ |
| 9 | No tools enabled | Admin → Workspace → Tools → empty | ☐ |
| 10 | No new functions | Admin → Workspace → Functions → empty | ☐ |
| 11 | RAG answer correct | New chat → question from PDF → correct answer | ☐ |
| 12 | Not-found decline works | Question NOT in PDFs → "Não encontrei..." | ☐ |
| 13 | Diagnosis refusal works | "Diagnostique meu caso" → refusal | ☐ |
| 14 | Temperature still 0.3 | Admin → Workspace → Models → Advanced | ☐ |
| 15 | Check release notes for new features | Disable any new tool/search/function features | ☐ |

---

## 8. Secret Rotation

### Quick reference

| Secret | Rotate with | Downtime | Side effect |
|--------|-----------|----------|-------------|
| `OPENAI_API_KEY` | `./scripts/rotate-secrets.sh openai` | ~10–30s | None |
| `WEBUI_SECRET_KEY` | `./scripts/rotate-secrets.sh webui` | ~10–30s | All users logged out |
| `POSTGRES_PASSWORD` | `./scripts/rotate-secrets.sh postgres` | ~10–30s | None if done in order |

### Check current secret status

```bash
./scripts/rotate-secrets.sh check
```

Shows masked key prefix, secret length, and `.env` modification date.

### When to rotate

| Trigger | Urgency |
|---------|---------|
| Key possibly exposed (in logs, git, shared) | **Immediate** |
| Team member leaves | Within 24 hours |
| Periodic hygiene | Every 90 days |

### Manual rotation (if the script doesn't suit you)

**OPENAI_API_KEY:**
```bash
# 1. Create new key at https://platform.openai.com/api-keys
# 2. Edit .env → replace OPENAI_API_KEY value
# 3. Restart
$COMPOSE restart open-webui
# 4. Verify: Admin → Settings → Connections → green
# 5. Revoke old key at OpenAI dashboard
```

**WEBUI_SECRET_KEY:**
```bash
# 1. Generate new secret
openssl rand -hex 32
# 2. Edit .env → replace WEBUI_SECRET_KEY value
# 3. Restart
$COMPOSE restart open-webui
# 4. All users are logged out — log in again to verify
```

**POSTGRES_PASSWORD (prod only):**
```bash
# ORDER MATTERS — change database first, then .env, then restart

# 1. Generate new password
NEW_PW=$(openssl rand -hex 16) && echo "$NEW_PW"

# 2. Change inside PostgreSQL
docker exec medique-postgres psql -U medique -c "ALTER USER medique PASSWORD '$NEW_PW';"

# 3. Edit .env → replace POSTGRES_PASSWORD with the new value

# 4. Restart Open WebUI (reads new DATABASE_URL from .env)
$COMPOSE restart open-webui

# 5. Verify health
$COMPOSE ps
```

---

## 9. Changing the Chat Model

### Switching default model (e.g., gpt-4o-mini → gpt-4o)

This changes which model students use for chat. It does NOT affect embeddings.

```bash
# 1. Edit .env
#    Change: DEFAULT_MODELS=gpt-4o
#    (This sets the default for new chats)

# 2. Restart to pick up the new default
$COMPOSE restart open-webui
```

Then in the Admin UI:

1. Go to **Admin → Workspace → Models**
2. Find the new model (`gpt-4o`) → edit
3. Under **Knowledge**, add your collection(s)
4. Under **Advanced Params**, set **Temperature** to `0.3`
5. Set the **System Prompt** if using per-model prompts
6. Save

### Validation after model change

Run the minimum regression set from `docs/bot-behavior/test-matrix.md`:

| Test | What | Expected |
|------|------|----------|
| A1 | Grounded answer | Answers from PDF content |
| B1 | Not-found decline | "Não encontrei..." |
| C1 | Diagnosis refusal | Refuses |
| D1 | Prescription refusal | Refuses |
| E1 | Emergency redirect | Mentions SAMU 192 |
| K5 | Common topic not in PDFs | Declines |

**If any test fails**, strengthen the system prompt or revert to the previous model.

### Rollback to previous model

```bash
# Edit .env → DEFAULT_MODELS=gpt-4o-mini
$COMPOSE restart open-webui
```

Verify the old model still has its Knowledge binding and temperature settings.

### Changing the embedding model

**This is a major operation.** Changing the embedding model (e.g., `text-embedding-3-small` → `text-embedding-3-large`) invalidates ALL existing embeddings. Every document must be re-embedded.

```bash
# 1. Backup
./scripts/backup.sh

# 2. Edit .env → RAG_EMBEDDING_MODEL=text-embedding-3-large

# 3. Restart
$COMPOSE restart open-webui

# 4. Delete ALL Knowledge collections in the Admin UI
#    Admin → Knowledge → delete each collection

# 5. Re-create collections and re-upload ALL PDFs

# 6. Re-bind collections to models
#    Admin → Workspace → Models → (model) → Knowledge → add collections

# 7. Re-run retrieval quality tests (docs/checklists.md, Checklist 2)
```

**Cost**: embedding API calls for every document. Plan during low-usage hours.

**Rollback**: restore from backup taken in step 1.

---

## 10. Document Re-Ingestion

### When to re-ingest

| Trigger | What to re-upload |
|---------|------------------|
| Course materials updated (new edition) | Replace old file with new version |
| OCR quality was poor | Re-OCR, re-upload |
| Embedding model changed | ALL documents (see section 9) |
| Retrieval quality degraded after Open WebUI update | Test first; re-upload only if needed |
| Module added to course | Upload new files only |
| Module removed from course | Delete file from collection |
| Duplicate content found | Remove duplicates |
| Dev → Production migration | Re-upload everything (separate databases) |

### Re-upload a single file

```
1. Admin → Knowledge → select collection
2. Find the old file → delete it
3. Upload the new version
4. Wait for processing to complete
5. Test retrieval:
   - Ask a question the new file answers
   - Ask about changed content → verify updated answer
   - Ask about removed content → verify "não encontrei"
```

### Re-upload an entire collection

Use when many files changed or the collection is corrupted.

```
1. Note the collection name and which model it's bound to
2. Admin → Knowledge → delete the collection
3. Create a new collection with the same name
4. Upload all current PDF files
5. Wait for processing
6. Re-bind to the model:
   Admin → Workspace → Models → (model) → Knowledge → add collection
7. Run the 5-question retrieval test (docs/rag-operations.md)
```

### Re-ingest all documents (full reset)

Required after changing the embedding model.

```bash
# 1. Backup first
./scripts/backup.sh

# 2. Change embedding model in .env (if that's the trigger)
# 3. Restart
$COMPOSE restart open-webui
```

Then in the Admin UI:

```
4. Delete ALL Knowledge collections
5. Re-create each collection
6. Upload all PDF files to their respective collections
7. Re-bind each collection to its model
8. Set temperature to 0.3 on each model
9. Run retrieval quality checklist (docs/checklists.md, Checklist 2)
```

**Estimated time**: 1–2 minutes per 100-page PDF for embedding. Plan accordingly.

---

## 11. Troubleshooting

### Container won't start

```bash
# Check what went wrong
$COMPOSE logs --tail 50 open-webui

# Common: missing env var
# Log shows: "Set OPENAI_API_KEY in .env"
# Fix: edit .env, set the variable, then:
$COMPOSE up -d
```

### Common issues and fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Container exits immediately | Missing required env var (fail-fast `${VAR:?}`) | Check `.env` for the variable mentioned in the error |
| "Connection refused" on localhost:3000 | Container not running | `$COMPOSE ps` then `$COMPOSE up -d` |
| Login page loads but login fails | Wrong password, or WEBUI_SECRET_KEY changed | Reset password via Admin UI, or restore `.env` and restart |
| OpenAI shows red/disconnected | Invalid or expired API key | Verify key at platform.openai.com; update `.env`; restart |
| Chat returns errors | OpenAI API issue (rate limit, outage, billing) | Check `$COMPOSE logs --tail 20 open-webui`; check https://status.openai.com |
| RAG returns wrong answers | Collection not bound, or PDF extraction issue | Check binding in Admin → Models → Knowledge; re-test with exact PDF terms |
| RAG returns "não encontrei" for content that IS in PDF | Embedding mismatch or chunk too small | Re-phrase question; check chunk size (1000); increase top-k (5→8) |
| PDF upload fails (prod) | Nginx body size limit | Check `client_max_body_size` in `nginx.conf` (default 100M) |
| PDF upload fails (dev) | File too large or password-protected | Split large PDFs; remove password protection |
| SSL errors (prod) | Expired cert or missing cert files | Check `ls reverse-proxy/ssl/`; renew with certbot |
| "Database is locked" (dev only) | SQLite concurrent access issue | Restart: `$COMPOSE restart open-webui` |
| Students see wrong model | DEFAULT_MODELS not set or model not available | Check `.env` DEFAULT_MODELS; verify model in Admin → Models |
| Slow responses | OpenAI API latency | Normal for long answers; switch to gpt-4o-mini if using gpt-4o |
| Container healthy but UI blank | Browser cache issue | Hard refresh (Ctrl+Shift+R) |

### Emergency procedures

**Bot is giving diagnoses (grounding failure):**
```bash
# Immediate: stop the service
$COMPOSE stop open-webui

# Fix: check and re-paste system prompt
# Then restart
$COMPOSE start open-webui
```

**API key compromised:**
```bash
# 1. Revoke at https://platform.openai.com/api-keys IMMEDIATELY
# 2. Create new key
# 3. Update .env
# 4. Restart
$COMPOSE restart open-webui
# 5. Verify: Admin → Settings → Connections → green
```

**Database corrupted (prod):**
```bash
# Restore from latest backup
./scripts/backup.sh  # backup current state just in case
$COMPOSE down
# Follow restore procedure in section 6
```

---

## 12. Monitoring

### Minimal monitoring (recommended for small operators)

You don't need Prometheus or Grafana. These checks are sufficient:

**Daily (takes 30 seconds):**
```bash
# Container still running?
$COMPOSE ps

# Health OK?
curl -sf http://localhost:3000/health && echo "OK"
```

**Weekly (takes 2 minutes):**
- Check OpenAI usage: https://platform.openai.com/usage
- Review backup log: `tail -20 /var/log/medique-backup.log`
- Spot-check one chat: Admin → Chats → look at recent conversations

**Monthly (takes 10 minutes):**
- Run retrieval quality tests (docs/checklists.md, Checklist 2)
- Run minimum regression test set (docs/bot-behavior/test-matrix.md)
- Check `.env` last modified date: `./scripts/rotate-secrets.sh check`
- Check disk usage: `docker system df`
- Review OpenAI spending trends

**After events:**
- After Open WebUI update → run post-update checklist (section 7)
- After PDF changes → run 5-question retrieval test
- After model change → run minimum regression set
- After secret rotation → verify connectivity

### Automated health check (optional)

Add to crontab to get notified on failure:

```bash
# Check every 5 minutes, send email on failure
*/5 * * * * curl -sf http://localhost:3000/health > /dev/null || echo "Medique is DOWN" | mail -s "ALERT: Medique Health Check Failed" admin@example.com
```

Or a simpler version that logs to a file:

```bash
*/5 * * * * curl -sf http://localhost:3000/health > /dev/null || echo "$(date) HEALTH CHECK FAILED" >> /var/log/medique-health.log
```

### Disk usage

```bash
# Docker disk usage summary
docker system df

# Volume sizes
docker system df -v | grep medique

# Clean unused images (safe — doesn't touch running containers)
docker image prune -f
```

---

## 13. Data Persistence

### Docker volumes

| Volume | Contents | Created by |
|--------|----------|-----------|
| `medique-webui-data` | SQLite (dev), uploads, internal config, ChromaDB (dev) | `docker-compose.yml` |
| `medique-postgres-data` | PostgreSQL data files + pgvector | `docker-compose.prod.yml` |

### What survives what

| Event | Data impact |
|-------|-------------|
| `$COMPOSE down` | Data preserved in volumes |
| `$COMPOSE down -v` | **All data deleted** |
| `$COMPOSE restart` | Data preserved |
| Server reboot | Containers auto-restart (`restart: unless-stopped`) |
| Open WebUI image update | Data preserved; migrations run automatically |
| `docker volume rm medique-webui-data` | **All Open WebUI data lost** |
| `docker volume rm medique-postgres-data` | **All PostgreSQL data lost** |

### Inspect volumes

```bash
# List project volumes
docker volume ls | grep medique

# Check volume size
docker run --rm -v medique-webui-data:/data alpine du -sh /data

# Browse volume contents
docker run --rm -v medique-webui-data:/data alpine ls -la /data
```

---

## Quick Reference Card

Copy this to your desk or bookmark it.

| Task | Command |
|------|---------|
| **Start (dev)** | `docker compose up -d` |
| **Start (prod)** | `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` |
| **Stop** | `$COMPOSE down` |
| **Restart** | `$COMPOSE restart` |
| **Status** | `$COMPOSE ps` |
| **Logs (live)** | `$COMPOSE logs -f open-webui` |
| **Logs (last 50)** | `$COMPOSE logs --tail 50 open-webui` |
| **Health** | `curl -sf http://localhost:3000/health` |
| **Backup** | `./scripts/backup.sh` |
| **Rotate secret** | `./scripts/rotate-secrets.sh {openai\|webui\|postgres\|check}` |
| **Update** | `./scripts/backup.sh && $COMPOSE pull open-webui && $COMPOSE up -d open-webui` |
| **Shell into container** | `docker exec -it medique-webui bash` |
| **PostgreSQL shell** | `docker exec -it medique-postgres psql -U medique` |
| **Disk usage** | `docker system df` |
