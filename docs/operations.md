# Operations

Day-to-day operational procedures for the medique-hostedui platform.

## Health Checks

### Container status

```bash
# Development
docker compose ps

# Production
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

All services should show `Up` and `(healthy)`.

### Open WebUI health endpoint

```bash
# Dev
curl -s http://localhost:3000/health

# Prod
curl -s https://yourdomain.com/health
```

Expected response: a 200 status code.

### Logs

```bash
# Follow Open WebUI logs
docker compose logs -f open-webui

# Follow all services (prod)
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f

# Last 100 lines of a specific service
docker compose logs --tail 100 open-webui
```

### Common issues

| Symptom | Check |
|---------|-------|
| Container not starting | `docker compose logs open-webui` — look for missing env vars |
| "Connection refused" on localhost:3000 | Is the container running? `docker compose ps` |
| OpenAI API errors in chat | Verify `OPENAI_API_KEY` in `.env`, check OpenAI status page |
| RAG not returning relevant results | Is the Knowledge collection attached to the model? |
| Slow responses | OpenAI API latency. Consider `gpt-4o-mini` if using `gpt-4o` |
| PDF upload fails | Check `client_max_body_size` in nginx.conf (default 100M) |
| SSL errors (prod) | Check cert files exist in `reverse-proxy/ssl/`, check expiry |

---

## Backup

### What to back up

| Data | Location | Priority | Recreatable? |
|------|----------|----------|-------------|
| PostgreSQL database | `medique-postgres-data` volume | **Critical** | No — contains users, chats, settings |
| Open WebUI data | `medique-webui-data` volume | **High** | Partially — contains uploads and local config |
| Original PDFs | External storage (not in Docker) | **Critical** | No — source material |
| `.env` file | Project root | **High** | No — contains secrets |

### Backup procedure

Use the provided backup script:

```bash
# Run backup (creates timestamped directory in ./backups/)
./scripts/backup.sh

# Run backup to a custom directory
./scripts/backup.sh /path/to/backup/storage
```

The script creates:
- `postgres.sql.gz` — full PostgreSQL dump, gzip compressed
- `webui-data.tar.gz` — full Open WebUI data volume archive

### Automated backups (production)

Add to crontab:

```bash
sudo crontab -e
```

```
0 2 * * * /path/to/medique-hostedui/scripts/backup.sh /path/to/backup/storage >> /var/log/medique-backup.log 2>&1
```

This runs daily at 2 AM.

### Restore procedure

```bash
# Restore PostgreSQL
gunzip -c backups/TIMESTAMP/postgres.sql.gz | docker exec -i medique-postgres psql -U medique medique

# Restore Open WebUI data
docker run --rm \
  -v medique-webui-data:/data \
  -v $(pwd)/backups/TIMESTAMP:/backup \
  alpine sh -c 'cd /data && tar xzf /backup/webui-data.tar.gz'
```

After restoring, restart the stack:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart
```

### Backup verification

Periodically test that backups are restorable:

1. Spin up a temporary dev environment.
2. Restore the backup into it.
3. Verify you can log in and chat.

---

## Updates

### Updating Open WebUI

```bash
# 1. Back up first
./scripts/backup.sh

# 2. Pull the latest image
docker compose pull open-webui

# 3. Recreate the container with the new image
docker compose up -d open-webui
# or for production:
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d open-webui
```

Open WebUI handles its own database migrations on startup.

### Pinning a version (recommended for production)

Instead of `:main` (latest), pin to a specific release tag:

```yaml
# In docker-compose.yml, change:
image: ghcr.io/open-webui/open-webui:main
# To:
image: ghcr.io/open-webui/open-webui:v0.5.0   # example
```

Check releases at: https://github.com/open-webui/open-webui/releases

### Updating Nginx (production)

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull nginx
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d nginx
```

### Updating PostgreSQL (production)

PostgreSQL major version upgrades require a `pg_dump` + restore cycle. Do not simply change the image tag.

```bash
# 1. Backup
./scripts/backup.sh

# 2. Stop the stack
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# 3. Change image tag in docker-compose.prod.yml
# 4. Remove old volume (DESTRUCTIVE)
docker volume rm medique-postgres-data

# 5. Start the stack (creates new empty database)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# 6. Restore from backup
gunzip -c backups/TIMESTAMP/postgres.sql.gz | docker exec -i medique-postgres psql -U medique medique
```

---

## Persistence

### Docker volumes

| Volume | Contents | Created by |
|--------|----------|-----------|
| `medique-webui-data` | Open WebUI SQLite (dev), uploads, internal config | `docker-compose.yml` |
| `medique-postgres-data` | PostgreSQL data files | `docker-compose.prod.yml` |

Volumes persist across `docker compose down` and `docker compose up -d`. They are only deleted with `docker compose down -v` or `docker volume rm`.

### What happens if...

| Event | Data Impact |
|-------|-------------|
| `docker compose down` | Containers stopped. Volumes and data preserved. |
| `docker compose down -v` | **Volumes deleted.** All data lost. |
| `docker compose up -d` after down | Data restored from volumes. |
| Server reboot | Containers restart automatically (`restart: unless-stopped`). |
| Open WebUI image update | Data preserved. Migrations run automatically. |
| `docker volume rm medique-webui-data` | **All Open WebUI data lost.** |

### Inspecting volumes

```bash
# List volumes
docker volume ls | grep medique

# Inspect volume details
docker volume inspect medique-webui-data

# Browse volume contents
docker run --rm -v medique-webui-data:/data alpine ls -la /data
```

---

## User Management

### Creating student accounts

Since signup is disabled, admin creates accounts:

1. Go to **Admin → Users → Add User**
2. Fill in name, email, password
3. Role: **User** (never Admin for students)
4. Share credentials with the student securely

### Resetting a student's password

1. Go to **Admin → Users**
2. Find the user and click edit
3. Set a new password

### Deactivating a student

1. Go to **Admin → Users**
2. Find the user and delete or deactivate

---

## Secret Rotation

Secrets should be rotated periodically or immediately if compromised. Full procedures with step-by-step commands are in [docs/security.md](security.md) under "Key Rotation".

### Quick reference

| Secret | Command to start rotation | Downtime | Side effects |
|--------|--------------------------|----------|-------------|
| `OPENAI_API_KEY` | `./scripts/rotate-secrets.sh openai` | ~10–30s restart | None — sessions preserved |
| `WEBUI_SECRET_KEY` | `./scripts/rotate-secrets.sh webui` | ~10–30s restart | **All users logged out** |
| `POSTGRES_PASSWORD` | `./scripts/rotate-secrets.sh postgres` | ~10–30s restart | None if done correctly |

### Checking secret age

```bash
./scripts/rotate-secrets.sh check
```

This shows when `.env` was last modified, as a rough indicator of when secrets were last rotated.

---

## Monitoring API Costs

1. Log in to https://platform.openai.com/usage
2. Check daily spending for your API key
3. Set a monthly spending limit at https://platform.openai.com/account/billing/limits

Cost drivers:
- **Embeddings**: one-time cost per PDF upload. Re-embedding only needed if you change the embedding model.
- **Chat completions**: per-message cost. GPT-4o-mini is ~20x cheaper than GPT-4o.

Typical cost estimate for a small class (50 students, moderate usage): $10–50/month with GPT-4o-mini.
