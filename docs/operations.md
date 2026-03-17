# Operations

Day-to-day operational overview for the medique-hostedui platform.

**For copy-paste procedures**, see [docs/runbook.md](runbook.md) — the complete operational runbook with exact commands.

---

## Quick Reference

| Task | Command |
|------|---------|
| Start (dev) | `docker compose up -d` |
| Start (prod) | `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` |
| Stop | `docker compose down` (or `$COMPOSE down` with prod files) |
| Restart a service | `$COMPOSE restart open-webui` |
| Logs (live) | `$COMPOSE logs -f open-webui` |
| Health check | `$COMPOSE ps` + `curl -sf http://localhost:3000/health` |
| Backup | `./scripts/backup.sh` |
| Rotate secrets | `./scripts/rotate-secrets.sh {openai|webui|postgres|check}` |
| Update | `./scripts/backup.sh && $COMPOSE pull open-webui && $COMPOSE up -d open-webui` |

---

## Health Checks

```bash
# Container status
$COMPOSE ps

# Health endpoint
curl -sf http://localhost:3000/health && echo "OK" || echo "FAIL"

# Logs
$COMPOSE logs --tail 100 open-webui
```

All services should show `Up` and `(healthy)`.

---

## Backup and Restore

**Backup:**
```bash
./scripts/backup.sh                     # → ./backups/YYYYMMDD_HHMMSS/
./scripts/backup.sh /custom/path        # → /custom/path/YYYYMMDD_HHMMSS/
```

**Automated (cron):**
```
0 2 * * * /path/to/medique-hostedui/scripts/backup.sh /mnt/backups >> /var/log/medique-backup.log 2>&1
```

**Restore:** see [runbook.md § 6. Restore](runbook.md#6-restore) for full procedure.

### What to back up

| Data | Priority | Recreatable? |
|------|----------|-------------|
| PostgreSQL database | Critical | No |
| Open WebUI data volume | High | Partially |
| Original PDFs | Critical | No |
| `.env` file | High | No |

---

## Updates

1. Back up: `./scripts/backup.sh`
2. Pull: `$COMPOSE pull open-webui`
3. Restart: `$COMPOSE up -d open-webui`
4. Validate: run post-update checklist in [runbook.md § 7](runbook.md#7-update-procedure)

**Pin to a version in production:**
```yaml
image: ghcr.io/open-webui/open-webui:v0.5.0   # not :main
```

**Rollback:** restore old image tag + restore from backup if needed.

---

## Persistence

| Volume | Contents |
|--------|----------|
| `medique-webui-data` | SQLite (dev), uploads, config, ChromaDB (dev) |
| `medique-postgres-data` | PostgreSQL data (prod) |

Volumes survive `down` and `restart`. Only `down -v` or `docker volume rm` deletes them.

---

## User Management

| Task | How |
|------|-----|
| Create student account | Admin → Users → Add User (role: User) |
| Reset password | Admin → Users → edit → new password |
| Deactivate student | Admin → Users → delete or deactivate |

Signup is disabled (`ENABLE_SIGNUP=false`). Admin creates all accounts.

---

## Secret Rotation

| Secret | Command | Downtime | Side effect |
|--------|---------|----------|-------------|
| `OPENAI_API_KEY` | `./scripts/rotate-secrets.sh openai` | ~10–30s | None |
| `WEBUI_SECRET_KEY` | `./scripts/rotate-secrets.sh webui` | ~10–30s | All users logged out |
| `POSTGRES_PASSWORD` | `./scripts/rotate-secrets.sh postgres` | ~10–30s | None if done in order |

Rotate every 90 days or immediately if compromised. Full procedures: [security.md](security.md) and [runbook.md § 8](runbook.md#8-secret-rotation).

---

## Monitoring API Costs

1. Log in to https://platform.openai.com/usage
2. Set monthly budget at https://platform.openai.com/account/billing/limits
3. Estimate: 50 students + GPT-4o-mini ≈ $10–50/month

---

## Common Issues

| Symptom | Fix |
|---------|-----|
| Container won't start | `$COMPOSE logs --tail 50 open-webui` — check for missing env vars |
| "Connection refused" on :3000 | `$COMPOSE ps` → `$COMPOSE up -d` |
| OpenAI errors in chat | Verify key in `.env`; check https://status.openai.com |
| RAG not finding content | Check Knowledge collection binding in Admin → Models → Knowledge |
| PDF upload fails (prod) | Check `client_max_body_size` in nginx.conf |
| SSL errors (prod) | Check cert files in `reverse-proxy/ssl/`; renew with certbot |

Full troubleshooting table: [runbook.md § 11](runbook.md#11-troubleshooting).

---

## Operational Schedules

| Frequency | Task | Reference |
|-----------|------|-----------|
| Daily | Check container health | `$COMPOSE ps` |
| Weekly | Review OpenAI usage, backup logs | runbook.md § 12 |
| Monthly | Retrieval quality tests, secret age check, disk usage | checklists.md, runbook.md § 12 |
| After updates | Post-update validation checklist | runbook.md § 7 |
| After PDF changes | 5-question retrieval test | rag-operations.md |
| After model changes | Minimum regression test set | test-matrix.md |
