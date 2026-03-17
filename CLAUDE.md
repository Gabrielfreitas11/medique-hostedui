# CLAUDE.md — medique-hostedui

Operational memory for AI-assisted development sessions.

## What this project is

A self-hosted educational chatbot for medical courses, built on Open WebUI + OpenAI API.
Students ask questions → the bot answers from uploaded course PDFs (RAG) → never from its own training data.

This is NOT a diagnostic tool. It's a course tutor.

## Stack

- **UI/Platform**: Open WebUI (Docker container)
- **LLM**: OpenAI API — GPT-4o-mini (default), GPT-4o (optional)
- **Embeddings**: OpenAI text-embedding-3-small
- **RAG**: Open WebUI built-in Knowledge + vector search
- **Database**: SQLite (dev) / PostgreSQL 16 + pgvector (prod)
- **Reverse proxy**: Nginx with SSL (production only)
- **Deployment**: Docker Compose

## Non-negotiable business rules

1. **RAG-only answers**: The model must answer from retrieved PDF context, not from parametric knowledge.
2. **No diagnosis**: System prompt explicitly forbids diagnoses, prescriptions, and clinical triage.
3. **Honest fallback**: If content isn't in the knowledge base → "Não encontrei essa informação no material do curso."
4. **No web search**: `ENABLE_RAG_WEB_SEARCH=false`. No search tools. No external knowledge.
5. **Didactic tone**: The bot is a tutor, not a clinician. Portuguese brasileiro.

## Repository layout

```
docker-compose.yml          ← dev stack (single container, SQLite)
docker-compose.prod.yml     ← prod override (adds Nginx + PostgreSQL)
.env.example                ← all env vars with docs; copy to .env
reverse-proxy/              ← Nginx config + SSL cert directory
config/system-prompts/      ← system prompt template (paste into Admin UI)
scripts/                    ← setup.sh, backup.sh, rotate-secrets.sh
knowledge/                  ← README only; PDFs managed via Open WebUI UI
docs/                       ← architecture, deployment, operations, security
```

## How Docker Compose works here

- `docker compose up -d` → development (single Open WebUI container on port 3000)
- `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` → production (Nginx + Open WebUI + PostgreSQL)
- The prod file overrides the dev file: removes published port, adds DATABASE_URL, adds Nginx and PostgreSQL services
- Container names prefixed with `medique-`; volume names prefixed with `medique-`
- `.env` is loaded implicitly by Docker Compose from the project root

## What is configured WHERE

This is the most common source of confusion. Two configuration planes exist:

**Environment variables (.env + Docker)** — set before container starts:
- API keys, auth settings, RAG engine/model, signup toggle, database URL
- Provider flags: `ENABLE_OPENAI_API=true`, `ENABLE_OLLAMA_API=false`
- UI branding: `WEBUI_NAME`
- Three sensitive secrets: `OPENAI_API_KEY`, `WEBUI_SECRET_KEY`, `POSTGRES_PASSWORD`
- Rotation via `scripts/rotate-secrets.sh {openai|webui|postgres|check}`

**Open WebUI Admin UI** — set after container is running:
- System prompt, Knowledge collections, model↔collection binding, RAG chunk settings, temperature, user accounts, web search toggle, tools

The system prompt text lives in `config/system-prompts/medical-tutor.md` as a template,
but must be **manually pasted** into Admin → Settings → General → System Prompt.
There is no automated way to inject it.

## Conventions

- Real secrets (`.env`, SSL certs) are gitignored. Only `.env.example` is committed.
- All documentation uses lowercase filenames (`docs/architecture.md`, not `ARCHITECTURE.md`).
- Scripts are in `scripts/` and must be executable (`chmod +x`).
- No custom application code — this project configures and deploys Open WebUI, it doesn't extend it.
- Changes to architecture or constraints must update this file.

## Current phase

**Phase 1 — Repository structure and local dev setup** (complete — 2026-03-16)
**Phase 2 — OpenAI provider setup, secrets management, verification** (complete — 2026-03-16)

Next: set `OPENAI_API_KEY` in `.env`, run `docker compose up -d`, follow verification checklist in `docs/deployment.md`.

## Open questions (do not block current phase)

- SSO/OAuth integration with course platform (Hotmart, Kiwify) — future
- Embed via iframe vs. direct link for students — future
- Cross-encoder reranking for better RAG retrieval — future
- One Knowledge collection per course vs. unified — future
- Chat log retention policy for LGPD compliance — future
- Open WebUI image version pinning for production — decide before prod deploy
