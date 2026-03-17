# Security

## Threat Model

| # | Threat | Likelihood | Impact | Mitigation |
|---|--------|-----------|--------|------------|
| T1 | Prompt injection — student tricks bot into giving diagnoses | Medium | High | System prompt constraints + low temperature + chat log review + disclaimer |
| T2 | API key leak via git or logs | Low | High | `.env` gitignored; key never in Compose file; `chmod 600` in prod |
| T3 | Unauthorized admin access | Low | High | Strong admin password; signup disabled; no default credentials |
| T4 | Unauthorized student access (link sharing) | Medium | Low | Auth required; admin creates accounts; educational content only |
| T5 | Data exfiltration (chat history, user data) | Low | Medium | PostgreSQL on internal network; encrypted backups; restricted access |
| T6 | Open WebUI zero-day | Low | High | Nginx as shield; pin image version in prod; monitor GitHub advisories |
| T7 | DDoS on public endpoint | Medium | Medium | Nginx rate limiting (10 req/s + burst 20); cloud provider firewall |
| T8 | LLM parametric leakage (answers from training data, not PDFs) | Medium | Medium | Cannot be fully eliminated; system prompt + monitoring mitigate |
| T9 | Student shares personal health info in chat | Low | Medium | System prompt warns against it; no PII collection by design |

## Authentication Configuration

| Setting | Value | How |
|---------|-------|-----|
| Authentication enabled | `true` | `WEBUI_AUTH=true` in `.env` |
| Self-registration | `false` (after admin setup) | `ENABLE_SIGNUP=false` in `.env` |
| JWT secret | Strong random string | `WEBUI_SECRET_KEY` — generate with `openssl rand -hex 32` |
| Admin account | Created on first launch | First registered user becomes admin |
| Student role | `User` | Admin creates accounts via Admin → Users |

## Network Security

### Docker network isolation (production)

```
Internet → Nginx (:443)
              │
              ├── frontend network ──── Open WebUI
              │
              └─────────────────────── PostgreSQL
                   backend network
                   (internal: true)
```

- `backend` network has `internal: true` — no internet access, no host access
- PostgreSQL port is **never** published to the host
- Only Nginx exposes ports 80 and 443

### Nginx hardening (reverse-proxy/nginx.conf)

Already configured:
- HTTP → HTTPS redirect
- TLS 1.2+ only, strong cipher suite
- HSTS header (2 years, includeSubDomains, preload)
- X-Frame-Options: SAMEORIGIN
- X-Content-Type-Options: nosniff
- Rate limiting: 10 req/s per IP with burst of 20
- WebSocket support for streaming responses
- 300s proxy timeout for long LLM responses

## Secrets Management

### What must NEVER be committed to git

- `.env` (real values)
- `reverse-proxy/ssl/*.pem`, `*.key`, `*.crt`
- Any file containing `OPENAI_API_KEY`, `WEBUI_SECRET_KEY`, or `POSTGRES_PASSWORD`

All of these are covered by `.gitignore`.

### Development

Secrets live in `.env` at the project root (gitignored). Acceptable for local dev.

### Production

Options in order of increasing security:

1. **`.env` file with `chmod 600`** — minimum viable. File readable only by the deploying user.
2. **Docker secrets** — pass secrets as files mounted into containers. Requires modifying the Compose file.
3. **External secrets manager** (Vault, AWS Secrets Manager, etc.) — inject at deploy time. Best for teams.

For a single-server deployment, option 1 is sufficient.

### API key hygiene

- Use a **dedicated** OpenAI API key for this project (not a personal key)
- Set a **monthly spending limit** in the OpenAI dashboard
- **Rotate** the key if you suspect compromise
- Monitor usage at https://platform.openai.com/usage

## Key Rotation

### When to rotate

| Trigger | Which secret | Urgency |
|---------|-------------|---------|
| Suspected compromise (key in logs, git, shared accidentally) | The compromised one | **Immediate** |
| Team member leaves the project | All secrets | Within 24 hours |
| Periodic hygiene | `OPENAI_API_KEY`, `WEBUI_SECRET_KEY` | Every 90 days (recommended) |
| Never rotated since creation | All secrets | Next maintenance window |

### How to rotate OPENAI_API_KEY

```bash
# 1. Create a new key at https://platform.openai.com/api-keys
#    Name it with a date: "medique-prod-2026-03"

# 2. Update .env with the new key
#    (edit the OPENAI_API_KEY= line)

# 3. Restart Open WebUI to pick up the new key
docker compose restart open-webui
# or for production:
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart open-webui

# 4. Verify the connection works
#    Open Admin → Settings → Connections → check OpenAI status

# 5. Revoke the OLD key at https://platform.openai.com/api-keys
#    Only after confirming step 4 succeeded
```

**Downtime**: ~10–30 seconds during container restart. Students will see a brief disconnection.

### How to rotate WEBUI_SECRET_KEY

```bash
# 1. Generate a new secret
openssl rand -hex 32

# 2. Update .env with the new value
#    (edit the WEBUI_SECRET_KEY= line)

# 3. Restart Open WebUI
docker compose restart open-webui

# 4. SIDE EFFECT: all active user sessions are invalidated.
#    Every student and admin must log in again.
```

**Impact**: All users are logged out immediately. Plan for off-hours.

### How to rotate POSTGRES_PASSWORD (production)

This is the most disruptive rotation because both PostgreSQL and Open WebUI must be updated.

```bash
# 1. Generate a new password
openssl rand -hex 16

# 2. Update .env with the new POSTGRES_PASSWORD value

# 3. Change the password inside PostgreSQL
docker exec -it medique-postgres psql -U medique -c "ALTER USER medique PASSWORD 'new-password-here';"

# 4. Restart Open WebUI (it reads DATABASE_URL from .env on startup)
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart open-webui

# 5. Verify Open WebUI starts correctly
docker compose ps
docker compose logs --tail 20 open-webui
```

**IMPORTANT**: Steps 3 and 4 must happen in sequence. If you restart Open WebUI before changing the PostgreSQL password, it will fail to connect.

### Using the rotation helper script

A convenience script is provided:

```bash
./scripts/rotate-secrets.sh openai      # rotates OPENAI_API_KEY
./scripts/rotate-secrets.sh webui        # rotates WEBUI_SECRET_KEY
./scripts/rotate-secrets.sh postgres     # rotates POSTGRES_PASSWORD
./scripts/rotate-secrets.sh check        # checks age of current secrets
```

See `scripts/rotate-secrets.sh` for details.

---

## Environment Management

### Secret lifecycle

```
.env.example (committed)        .env (gitignored, per-machine)
  │                                │
  │  cp .env.example .env          │  contains real secrets
  │  (one-time setup)              │  chmod 600 in production
  │                                │
  │  placeholder values            │  read by docker compose
  │  documentation                 │  read by scripts/setup.sh
  └────────────────────────────────┘
```

### Rules

1. **`.env.example` is the schema.** It documents every variable, its purpose, and its format. It is committed to git with placeholder values only.

2. **`.env` is the instance.** It contains real secrets for the current machine. It is never committed. It is created once by copying `.env.example`.

3. **One `.env` per machine.** Dev laptop has its own `.env`. Prod server has its own `.env`. They use different keys, different passwords, different secrets.

4. **No intermediate env files.** Earlier phases used `config/env/.env.dev.example` and `.env.prod.example` — those were consolidated into a single `.env.example` at the root. The `.env` file has a production section that you uncomment when deploying.

5. **Secrets never appear in Docker Compose files.** Compose files reference variables with `${VAR}` syntax. The values come from `.env`.

6. **Fail-fast on missing secrets.** Critical variables use `${VAR:?error message}` syntax in Compose, which stops the stack immediately if the variable is unset — rather than starting silently with no API access.

### Backup your .env

Your `.env` contains secrets that cannot be recovered if lost. Include it in your backup strategy:

- **Option A**: Manually copy `.env` to your backup location alongside database backups
- **Option B**: Use `./scripts/backup.sh` which reminds you to back up `.env` separately
- **Option C**: Store secrets in a password manager (1Password, Bitwarden) as a recovery fallback

---

## RAG Constraint Layers

The bot's restriction to course content relies on four independent layers. No single layer is sufficient alone.

| Layer | Mechanism | Controlled via |
|-------|-----------|---------------|
| 1. System prompt | Instructs model to answer only from context | Admin UI → System Prompt |
| 2. Knowledge binding | Attaches PDF collection to model for retrieval | Admin UI → Models → Knowledge |
| 3. Environment flags | `ENABLE_RAG_WEB_SEARCH=false`, `ENABLE_SEARCH_QUERY=false` | `.env` |
| 4. No tools/functions | No external tools enabled | Admin UI → Tools (empty) |

### Known limitation: parametric leakage

GPT-4o has extensive medical knowledge from training. The system prompt instructs it to answer only from provided context, but:
- This is a behavioral instruction, not a hard constraint
- Adversarial prompting can sometimes bypass it
- The model may "fill in" answers when retrieved context is partially relevant

**Mitigations**: low temperature (0.3), strong prompt wording, periodic chat log review, visible disclaimer.

## Content Safety

### Disclaimer

Students should see a clear disclaimer that this is an educational tool, not a medical advisor. Options:

1. Include it in the system prompt's response format (already done in `medical-tutor.md`)
2. Set a banner message in Open WebUI (if available in your version: Admin → Settings → General → Banner)
3. Add it to the welcome/onboarding message for new users

### Chat log review

Periodically review chat logs (Admin → Chats or Admin → Users → user → Chats) for:
- Responses that cite information not in the course PDFs
- Successful prompt injection attempts
- Students sharing personal health information
- Inappropriate bot behavior

### No PII collection

The system prompt discourages students from sharing personal health info. However, if they do, it's stored in the chat database. Consider:
- A data retention policy (delete chats older than X days) — Phase 2+
- LGPD compliance review if operating in Brazil — Phase 2+

## Update Strategy

| Component | Recommendation |
|-----------|---------------|
| Open WebUI | Pin to a specific tag in prod (not `:main`). Test updates in dev first. |
| Nginx | Update Alpine-based image periodically. Low risk. |
| PostgreSQL | Minor version updates are safe. Major versions require dump + restore. |
| SSL certificates | Auto-renewed by Certbot cron job (see docs/deployment.md). |
