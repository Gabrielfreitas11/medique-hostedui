# Deployment

## Prerequisites

- Docker Engine 24+ with Compose v2 (`docker compose version`)
- An OpenAI API key with access to GPT-4o-mini and text-embedding-3-small
- (Production) A Linux server with a public IP and a domain pointing to it
- (Production) Ports 80 and 443 open in the firewall

## Local Development

### 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set `OPENAI_API_KEY` to your real key. All other defaults work for dev.

### 2. Start the stack

```bash
docker compose up -d
```

This pulls the Open WebUI image and starts a single container with SQLite storage.

### 3. First-time setup in the UI

Open `http://localhost:3000` in your browser.

**Step 1 — Create admin account**

The first user to register becomes the admin. Use a strong password.

**Step 2 — Disable signup**

After creating your admin account:
- Go to **Admin → Settings → General**
- Turn off **Enable New Sign Ups** (or set `ENABLE_SIGNUP=false` in `.env` and restart)

**Step 3 — Set the system prompt**

- Go to **Admin → Settings → General → System Prompt**
- Copy the prompt text from `config/system-prompts/medical-tutor.md` (the text between the `---` markers)
- Paste it and save

**Step 4 — Configure RAG settings**

- Go to **Admin → Settings → Documents**
- Set **Chunk Size**: `1000`
- Set **Chunk Overlap**: `200`
- Confirm **Embedding Model** is `text-embedding-3-small`

**Step 5 — Create a Knowledge collection**

- Go to **Admin → Knowledge → New Collection**
- Name it (e.g., "Curso de Medicina — Módulo 1")
- Upload one or more course PDFs
- Wait for embedding to complete

**Step 6 — Bind collection to model**

- Go to **Admin → Workspace → Models**
- Find `gpt-4o-mini` and click the edit icon
- Under **Knowledge**, add your collection
- Under **Advanced Params**, set **Temperature** to `0.3`
- Save

**Step 7 — Verify RAG behavior**

- Go to **Admin → Settings → Web Search** → confirm web search is **OFF**
- Go to **Admin → Workspace → Tools** → confirm **no tools are enabled**

**Step 8 — Test**

Open a new chat and test these scenarios:

| Test | Expected Result |
|------|-----------------|
| Question covered by PDF | Answer based on course content, educational tone |
| Question NOT in PDF | "Não encontrei essa informação no material do curso" |
| "Diagnostique minha dor de cabeça" | Refusal — "Como tutor educacional, não posso..." |
| Generic medical question not in PDF | Refusal or redirect to course material |

### 4. Stop / restart

```bash
docker compose down       # stop (data persists in volume)
docker compose up -d      # start again
```

### 5. Reset everything (destroys data)

```bash
docker compose down -v    # removes volumes — all data lost
```

---

## Production Deployment

### 1. Server setup

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER
# Log out and back in for group membership to take effect
```

### 2. Clone repository

```bash
git clone <your-repo-url> medique-hostedui
cd medique-hostedui
```

### 3. Configure environment

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` with production values:

```bash
# Required changes for production:
OPENAI_API_KEY=sk-your-production-key
WEBUI_SECRET_KEY=$(openssl rand -hex 32)    # generate and paste
ENABLE_SIGNUP=false

# PostgreSQL
POSTGRES_USER=medique
POSTGRES_PASSWORD=$(openssl rand -hex 16)   # generate and paste
POSTGRES_DB=medique
```

### 4. SSL certificates with Certbot

```bash
# Install Certbot
sudo apt install -y certbot

# Obtain certificates (ensure port 80 is free and DNS points to this server)
sudo certbot certonly --standalone -d yourdomain.com

# Copy to project
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem reverse-proxy/ssl/
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem reverse-proxy/ssl/
sudo chown $USER:$USER reverse-proxy/ssl/*.pem
```

### 5. Start the production stack

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

This starts three containers:
- `medique-webui` — Open WebUI connected to PostgreSQL
- `medique-postgres` — PostgreSQL 16 with pgvector
- `medique-nginx` — Nginx with SSL on ports 80/443

### 6. First-time setup

Open `https://yourdomain.com` and follow the same UI setup steps as local development (steps 1–8 above). Since `ENABLE_SIGNUP=false`, you will need to temporarily set it to `true` in `.env` and restart, or create the first user before setting it to `false`.

Alternative approach: start with `ENABLE_SIGNUP=true`, create your admin, then:

```bash
# Edit .env to set ENABLE_SIGNUP=false, then:
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart open-webui
```

### 7. SSL auto-renewal

```bash
# Add to crontab (run as root or with sudo)
sudo crontab -e
```

Add this line:

```
0 3 1,15 * * certbot renew --quiet && cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem /path/to/medique-hostedui/reverse-proxy/ssl/ && cp /etc/letsencrypt/live/yourdomain.com/privkey.pem /path/to/medique-hostedui/reverse-proxy/ssl/ && docker compose -f /path/to/medique-hostedui/docker-compose.yml -f /path/to/medique-hostedui/docker-compose.prod.yml exec nginx nginx -s reload
```

This attempts renewal on the 1st and 15th of each month at 3 AM.

---

## OpenAI Provider Setup

### How Open WebUI connects to OpenAI

Open WebUI connects to OpenAI via two environment variables set in `.env`:

- `OPENAI_API_KEY` — authenticates all API calls (chat completions + embeddings)
- `OPENAI_API_BASE_URL` — the API endpoint (default: `https://api.openai.com/v1`)

Two feature flags control which LLM providers are visible in the Admin UI:

- `ENABLE_OPENAI_API=true` — shows the OpenAI connection panel
- `ENABLE_OLLAMA_API=false` — hides the Ollama panel (we don't use it)

When the container starts with a valid `OPENAI_API_KEY`, Open WebUI automatically discovers all models available to that key. There is no manual model registration step.

### What your OpenAI API key needs access to

| Capability | Model | Required for |
|-----------|-------|-------------|
| Chat Completions | `gpt-4o-mini` | Student chat (default model) |
| Chat Completions | `gpt-4o` | Optional — higher quality, higher cost |
| Embeddings | `text-embedding-3-small` | RAG document indexing and query embedding |

Verify your key has access by running this from any terminal:

```bash
curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer sk-your-key-here" \
  | grep -o '"id":"[^"]*"' | head -20
```

You should see `gpt-4o-mini`, `gpt-4o`, and `text-embedding-3-small` in the output.

### Creating a dedicated API key

1. Go to https://platform.openai.com/api-keys
2. Click **Create new secret key**
3. Name it something identifiable: `medique-hostedui-prod` or `medique-hostedui-dev`
4. Copy the key immediately — it won't be shown again
5. Paste into your `.env` file as `OPENAI_API_KEY=sk-...`

**Why a dedicated key?** If this key is compromised, you can revoke it without affecting your other projects. It also makes cost tracking easier — you can see exactly how much this project spends.

### Setting a spending limit

1. Go to https://platform.openai.com/account/billing/limits
2. Set a **monthly budget limit** appropriate for your student count
3. Estimate: 50 students with moderate usage ≈ $10–50/month with `gpt-4o-mini`

### Using an OpenAI-compatible provider (alternative)

If you want to use a different provider that exposes an OpenAI-compatible API (e.g., Azure OpenAI, Together AI, Groq), change `OPENAI_API_BASE_URL` to point to their endpoint. The key format and model names may differ — consult the provider's documentation.

### Verifying the connection after startup

After `docker compose up -d`, verify the OpenAI connection is working:

1. Open `http://localhost:3000` and log in as admin
2. Go to **Admin → Settings → Connections**
3. Under **OpenAI API**, you should see:
   - URL: `https://api.openai.com/v1`
   - A green indicator or checkmark confirming the connection
   - If you see a red error, check your `OPENAI_API_KEY` in `.env`
4. Click the **refresh/verify** button if available to test the connection
5. Go to **Admin → Workspace → Models** — you should see OpenAI models listed (gpt-4o, gpt-4o-mini, etc.)

If no models appear:
- Check `ENABLE_OPENAI_API=true` in `.env`
- Check container logs: `docker compose logs open-webui | grep -i openai`
- Verify the key hasn't expired or been revoked

---

## Security-Sensitive Configuration

### Inventory of secrets

This project uses three secrets. All live in `.env` (gitignored).

| Secret | Variable | Where it's used | Impact if leaked |
|--------|----------|----------------|-----------------|
| OpenAI API key | `OPENAI_API_KEY` | Sent to OpenAI on every chat and embedding request | Attacker can make API calls on your account (financial impact) |
| JWT signing secret | `WEBUI_SECRET_KEY` | Signs session tokens for all logged-in users | Attacker can forge session tokens and impersonate any user including admin |
| PostgreSQL password | `POSTGRES_PASSWORD` | Open WebUI → PostgreSQL connection string | Attacker can read/modify database (users, chats, settings) — only exploitable if they reach the Docker network |

### How secrets flow through the system

```
.env file (root of project, chmod 600 in prod)
  │
  ├── docker compose reads .env automatically
  │
  ├── OPENAI_API_KEY → passed as env var to open-webui container
  │                     → sent in Authorization header to api.openai.com
  │                     → NEVER sent to the browser
  │
  ├── WEBUI_SECRET_KEY → passed as env var to open-webui container
  │                      → used internally for JWT signing
  │                      → NEVER leaves the container
  │
  └── POSTGRES_PASSWORD → passed to both open-webui and postgres containers
                          → used in DATABASE_URL connection string
                          → traffic stays on internal Docker network
```

### Secret generation commands

```bash
# JWT secret (64 hex chars = 256 bits)
openssl rand -hex 32

# PostgreSQL password (32 hex chars = 128 bits)
openssl rand -hex 16

# OpenAI API key — created at https://platform.openai.com/api-keys
```

### Preventing accidental exposure

**Already in place:**
- `.gitignore` blocks `.env`, `.env.*`, and SSL cert files
- `.env.example` uses placeholder values only (`sk-change-me`, `dev-only-change-in-prod`)
- Docker Compose never contains secret values — only `${VARIABLE}` references
- The `OPENAI_API_KEY` uses `:?` syntax which makes Docker Compose fail immediately if the variable is missing, rather than silently starting with no API access
- `ENABLE_OLLAMA_API=false` prevents an unconfigured Ollama panel from confusing the setup

**You should also do:**
- Run `chmod 600 .env` on production servers (restricts read to file owner only)
- Never paste secrets into chat, issues, or documentation
- Never pass secrets as command-line arguments (they appear in `ps` output)
- Review `git diff --cached` before every commit to catch accidental `.env` staging
- If you suspect a key is compromised, rotate it immediately (see docs/operations.md)

### Production hardening checklist

Before going live, verify every item:

| # | Check | How to verify |
|---|-------|--------------|
| 1 | `OPENAI_API_KEY` is a dedicated production key | Check at https://platform.openai.com/api-keys |
| 2 | `WEBUI_SECRET_KEY` is a 64-char random hex string | `grep WEBUI_SECRET_KEY .env` — should not be `dev-only-change-in-prod` |
| 3 | `POSTGRES_PASSWORD` is a random string | `grep POSTGRES_PASSWORD .env` — should not contain placeholder text |
| 4 | `ENABLE_SIGNUP=false` | `grep ENABLE_SIGNUP .env` |
| 5 | `.env` has restricted permissions | `ls -la .env` — should show `-rw-------` |
| 6 | `.env` is not tracked by git | `git status .env` — should not appear |
| 7 | OpenAI spending limit is set | Check https://platform.openai.com/account/billing/limits |
| 8 | SSL certificates are in place | `ls reverse-proxy/ssl/` — should show `fullchain.pem` and `privkey.pem` |

---

## Verification Checklist

Run through this checklist after first setup (dev or prod) to confirm everything works.

### 1. Container health

```bash
docker compose ps
```

Expected: `medique-webui` is `Up` and `(healthy)`.

### 2. OpenAI connection

- Open `http://localhost:3000` (dev) or `https://yourdomain.com` (prod)
- Log in as admin
- Go to **Admin → Settings → Connections**
- Confirm OpenAI connection shows a green status
- If the Ollama section is visible and shows an error, that's OK — it's disabled and not used

### 3. Models are visible

- Go to **Admin → Workspace → Models**
- Confirm `gpt-4o-mini` appears in the model list
- If no models appear, check the OpenAI connection in step 2

### 4. System prompt is set

- Go to **Admin → Settings → General**
- Confirm the system prompt is filled in (from `config/system-prompts/medical-tutor.md`)
- If empty, paste it now

### 5. RAG settings are configured

- Go to **Admin → Settings → Documents**
- Confirm:
  - Embedding model: `text-embedding-3-small`
  - Chunk size: `1000`
  - Chunk overlap: `200`

### 6. Web search is disabled

- Go to **Admin → Settings → Web Search**
- Confirm web search is **OFF**

### 7. No tools are enabled

- Go to **Admin → Workspace → Tools**
- Confirm the list is empty (no tools enabled)

### 8. Signup is disabled (after admin account creation)

- Go to **Admin → Settings → General**
- Confirm **Enable New Sign Ups** is OFF
- Or verify `ENABLE_SIGNUP=false` in `.env`

### 9. Chat works

- Start a new chat
- Select `gpt-4o-mini` as the model
- Type "Olá, o que você pode me ajudar?"
- Expected: a response in educational-tutor tone
- If Knowledge collection is attached: response should reference course material

### 10. Branding is correct

- Check the browser tab and UI header
- Should show "Medique - Tutor Educacional" (or your custom `WEBUI_NAME`)

---

## Quick Reference

| Task | Command |
|------|---------|
| Start (dev) | `docker compose up -d` |
| Start (prod) | `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` |
| Stop | `docker compose down` |
| View logs | `docker compose logs -f open-webui` |
| Check health | `docker compose ps` |
| Rebuild after update | `docker compose pull && docker compose up -d` |
| Enter webui shell | `docker exec -it medique-webui bash` |
| PostgreSQL shell (prod) | `docker exec -it medique-postgres psql -U medique` |
