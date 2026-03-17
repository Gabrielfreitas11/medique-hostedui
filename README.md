# medique-hostedui

Self-hosted chatbot platform for medical education courses.
Built on [Open WebUI](https://github.com/open-webui/open-webui) + OpenAI API with RAG-based PDF knowledge retrieval.

## What this is

An educational chatbot that answers student questions based **exclusively** on uploaded course PDFs. It behaves as a course tutor — not a doctor, not a diagnostic tool.

## What this is NOT

- Not a medical diagnosis assistant
- Not a clinical decision support tool
- Not a general-purpose chatbot

## Quick Start (Development)

```bash
# 1. Configure
cp .env.example .env
# Edit .env → set OPENAI_API_KEY to your real key

# 2. Start
docker compose up -d

# 3. Open http://localhost:3000
#    - Create admin account (first user = admin)
#    - Verify OpenAI connection: Admin → Settings → Connections
#    - Set system prompt from config/system-prompts/medical-tutor.md
#    - Upload course PDFs to a Knowledge collection
#    - Bind the collection to the model
#    - Disable signup after admin account is created

# 4. Check secret status
./scripts/rotate-secrets.sh check
```

Full setup and verification checklist: [docs/deployment.md](docs/deployment.md)

## Architecture

```
Nginx (prod) → Open WebUI → OpenAI API
                   │
              PostgreSQL (prod)
              SQLite (dev)
```

- **Open WebUI**: Chat UI, authentication, RAG pipeline, Knowledge management
- **OpenAI API**: GPT-4o-mini (chat) + text-embedding-3-small (embeddings)
- **Nginx**: SSL termination and rate limiting (production only)
- **PostgreSQL + pgvector**: Relational data + vector search (production only)

Full architecture: [docs/architecture.md](docs/architecture.md)

## Documentation

| Document | Content |
|----------|---------|
| [docs/architecture.md](docs/architecture.md) | System design, components, data flow, config mapping |
| [docs/deployment.md](docs/deployment.md) | Local/prod deployment, OpenAI setup, verification checklist |
| [docs/runbook.md](docs/runbook.md) | Copy-paste operational runbook: startup, shutdown, backup, restore, update, troubleshooting |
| [docs/operations.md](docs/operations.md) | Operations overview with quick reference and schedules |
| [docs/security.md](docs/security.md) | Threat model, auth, network isolation, key rotation, env management |
| [docs/rag-operations.md](docs/rag-operations.md) | PDF preparation, upload, Knowledge collections, retrieval tuning, grounding |
| [docs/checklists.md](docs/checklists.md) | Ingestion, retrieval quality, hallucination debugging, re-upload, pre-launch |
| [docs/grounding-strategy.md](docs/grounding-strategy.md) | Grounding enforcement, enforceable vs policy controls, admin lockdown checklist |
| [docs/integration.md](docs/integration.md) | Course website integration: iframe, auth, per-course segregation, staged rollout |
| [docs/bot-behavior/](docs/bot-behavior/) | System prompt, refusal rules, style guide, examples, test matrix |

## Repository Structure

```
├── docker-compose.yml           ← development stack (single container)
├── docker-compose.prod.yml      ← production override (+Nginx, +PostgreSQL)
├── .env.example                 ← environment variable template
├── reverse-proxy/
│   ├── nginx.conf               ← Nginx config (production)
│   └── ssl/                     ← SSL certs (gitignored)
├── config/
│   └── system-prompts/
│       └── medical-tutor.md     ← system prompt template
├── scripts/
│   ├── setup.sh                 ← automated setup script
│   ├── backup.sh                ← database + volume backup
│   └── rotate-secrets.sh        ← guided secret rotation
├── knowledge/
│   └── README.md                ← PDF management instructions
└── docs/                        ← full documentation
```

## Key Business Rules

1. The bot answers **only** from uploaded course PDFs (RAG retrieval)
2. It **never** provides diagnoses, prescriptions, or clinical decisions
3. If the answer isn't in the course material, it says so honestly
4. Web search is **disabled** — no external knowledge sources
5. All responses use a didactic, educational tone

## License

Private repository. All rights reserved.
