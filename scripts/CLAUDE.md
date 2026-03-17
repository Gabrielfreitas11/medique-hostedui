# CLAUDE.md — scripts/

## Scripts in this directory

### setup.sh

Automated first-time setup. Validates prerequisites, checks `.env`, starts Docker Compose, waits for health.

```bash
./scripts/setup.sh           # development (default)
./scripts/setup.sh prod      # production
```

Behavior:
- Creates `.env` from `.env.example` if missing, then exits with instructions.
- Validates `OPENAI_API_KEY` is set (both envs) and `WEBUI_SECRET_KEY` + `POSTGRES_PASSWORD` (prod only).
- For prod, checks SSL cert files exist in `reverse-proxy/ssl/`.
- Starts the appropriate Docker Compose configuration.
- Waits up to 60 seconds for the health check to pass.

### backup.sh

Backs up PostgreSQL (if running) and the Open WebUI data volume.

```bash
./scripts/backup.sh                     # → ./backups/YYYYMMDD_HHMMSS/
./scripts/backup.sh /custom/path        # → /custom/path/YYYYMMDD_HHMMSS/
```

Outputs:
- `postgres.sql.gz` — full pg_dump, gzip compressed (skipped if PostgreSQL isn't running)
- `webui-data.tar.gz` — full data volume archive

Restore procedures are in `docs/operations.md`.

### rotate-secrets.sh

Interactive guided rotation for the three project secrets.

```bash
./scripts/rotate-secrets.sh openai      # rotate OPENAI_API_KEY
./scripts/rotate-secrets.sh webui       # rotate WEBUI_SECRET_KEY
./scripts/rotate-secrets.sh postgres    # rotate POSTGRES_PASSWORD (prod only)
./scripts/rotate-secrets.sh check       # show secret status and age
```

Behavior:
- Does NOT auto-generate or auto-inject the OpenAI key (must be created at platform.openai.com).
- Auto-generates `WEBUI_SECRET_KEY` and `POSTGRES_PASSWORD` values, but the user must manually paste them into `.env`.
- For PostgreSQL rotation, runs `ALTER USER` inside the container first, then prompts user to update `.env`, then restarts Open WebUI.
- `check` subcommand shows masked key prefixes, secret lengths, and `.env` modification date.
- Auto-detects dev vs prod by checking if `medique-postgres` container is running.

## Constraints

- Scripts must work on both macOS (dev) and Ubuntu (prod).
- Scripts source `.env` via `source` — variables must not contain unescaped special characters.
- No script should modify `.env` after initial creation. User edits it manually.
