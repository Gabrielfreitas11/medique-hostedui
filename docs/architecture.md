# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        INTERNET                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS :443
                           ▼
              ┌────────────────────────┐
              │   Nginx Reverse Proxy  │  ← production only
              │   (SSL termination)    │
              └───────────┬────────────┘
                          │ HTTP :8080
                          ▼
              ┌────────────────────────┐
              │     Open WebUI         │
              │  ┌──────────────────┐  │
              │  │  Chat UI         │  │
              │  │  User Auth       │  │
              │  │  RAG Pipeline    │  │
              │  │  Knowledge Mgmt  │  │
              │  └──────────────────┘  │
              └──┬──────────────┬──────┘
                 │              │
        ┌────────▼───┐   ┌─────▼──────────┐
        │  Database   │   │   OpenAI API   │
        │ SQLite(dev) │   │  GPT-4o-mini   │
        │ Postgres    │   │  Embeddings    │
        │  (prod)     │   └────────────────┘
        └─────────────┘
```

## Components

### Open WebUI

The core application. Provides chat UI, authentication, RAG pipeline, and Knowledge management.

**Image**: `ghcr.io/open-webui/open-webui:main`

Open WebUI handles:
- User authentication and role management (Admin / User)
- Chat interface with streaming responses
- Knowledge collections (PDF upload, chunking, embedding, retrieval)
- Model configuration and system prompt management
- Chat history storage

### Database

| Environment | Technology | Purpose |
|-------------|-----------|---------|
| Development | SQLite (built-in) | Users, chats, settings. Zero config. |
| Production | PostgreSQL 16 + pgvector | Same, plus native vector search for embeddings. |

Development uses SQLite because it requires no extra container. Open WebUI creates it automatically in its data volume.

Production uses PostgreSQL with the pgvector extension because:
- Concurrent access from multiple students
- Durability guarantees beyond SQLite
- pgvector provides native vector similarity search

### OpenAI API

External dependency. All API calls are made server-side by Open WebUI's backend — never from the browser.

| Model | Purpose | Cost Tier |
|-------|---------|-----------|
| `gpt-4o-mini` | Default chat model — fast, cheap, good for educational Q&A | Low |
| `gpt-4o` | Available to admin for complex queries (optional) | High |
| `text-embedding-3-small` | Document and query embedding for RAG | Low |

### Nginx (production only)

Reverse proxy for SSL termination, security headers, and rate limiting. Configuration in `reverse-proxy/nginx.conf`.

Not used in development — Open WebUI is accessed directly on `localhost:3000`.

## Data Flow

### Student asks a question

```
1. Student types question in chat UI
2. Open WebUI backend embeds the question (OpenAI text-embedding-3-small)
3. Vector search retrieves top-k relevant chunks from Knowledge collection
4. System prompt + retrieved chunks + question are assembled into a prompt
5. Prompt sent to OpenAI GPT-4o-mini
6. Streamed response displayed to student
```

### Admin uploads a course PDF

```
1. Admin uploads PDF via Knowledge UI
2. Open WebUI extracts text from PDF (built-in parser)
3. Text is split into chunks (configurable size and overlap)
4. Each chunk is embedded via OpenAI text-embedding-3-small
5. Embeddings stored in vector database (ChromaDB/SQLite in dev, pgvector in prod)
6. Chunks are searchable immediately
```

## What is configured WHERE

This is a critical distinction. Some settings live in environment variables (managed via `.env` and Docker), and some live inside Open WebUI's database (managed via the Admin UI).

### Configured via environment variables (.env + Docker)

These are set **before** the container starts and generally don't change at runtime.

| Variable | Purpose | Sensitive? |
|----------|---------|-----------|
| `OPENAI_API_KEY` | API authentication | **Yes** |
| `OPENAI_API_BASE_URL` | API endpoint | No |
| `ENABLE_OPENAI_API` | Show OpenAI connection panel (`true`) | No |
| `ENABLE_OLLAMA_API` | Show Ollama connection panel (`false`) | No |
| `WEBUI_AUTH` | Enable/disable authentication | No |
| `WEBUI_SECRET_KEY` | JWT signing secret | **Yes** |
| `ENABLE_SIGNUP` | Allow/block self-registration | No |
| `ENABLE_RAG_WEB_SEARCH` | Must be `false` | No |
| `ENABLE_SEARCH_QUERY` | Must be `false` | No |
| `RAG_EMBEDDING_ENGINE` | `openai` | No |
| `RAG_EMBEDDING_MODEL` | `text-embedding-3-small` | No |
| `WEBUI_NAME` | Custom UI title | No |
| `DEFAULT_MODELS` | Pre-selected model for new chats | No |
| `DATABASE_URL` | PostgreSQL connection (prod only) | **Yes** (contains password) |
| `POSTGRES_PASSWORD` | Database password (prod only) | **Yes** |

### Configured via Open WebUI Admin UI

These are stored in the database and changed through the web interface.

| Setting | Where in UI | Notes |
|---------|-------------|-------|
| Global system prompt | Admin → Settings → General → System Prompt | Paste from `config/system-prompts/medical-tutor.md` |
| Knowledge collections | Admin → Knowledge | Upload PDFs here |
| Model ↔ Knowledge binding | Admin → Workspace → Models → (model) → Knowledge | Activates RAG for the model |
| RAG chunk size / overlap | Admin → Settings → Documents | Recommended: 1000 / 200 |
| RAG top-k | Admin → Settings → Documents | Recommended: 5 |
| Model temperature | Admin → Workspace → Models → (model) → Advanced | Recommended: 0.3 |
| User accounts | Admin → Users | Create student accounts here |
| Web search toggle | Admin → Settings → Web Search | Confirm disabled |
| Tools / Functions | Admin → Workspace → Tools | No tools should be enabled |

## Network Topology

### Development

```
Browser → localhost:3000 → Open WebUI (SQLite + built-in ChromaDB)
                                 ↓
                           OpenAI API (internet)
```

Single container. No Nginx. No PostgreSQL.

### Production

```
Browser → Nginx :443 (SSL) →─┐
                              ├── frontend network
Open WebUI :8080 ─────────────┘
       │
       ├── backend network (internal, no internet access)
       │
PostgreSQL :5432 ──────────────┘
       │
Open WebUI → OpenAI API (internet)
```

Three containers. PostgreSQL is on an internal-only Docker network.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Open WebUI over custom app | Mature chat UI, built-in RAG, auth, Knowledge management. No need to reinvent. |
| OpenAI API over self-hosted LLM | Quality matters for medical education. Self-hosting (Llama, Mistral) is a future option. |
| `text-embedding-3-small` over `large` | Good quality/cost ratio. Upgrade path exists without architectural changes. |
| PostgreSQL + pgvector over dedicated vector DB | Fewer containers. Single DB for relational + vector data. |
| SQLite in dev, PostgreSQL in prod | Dev simplicity vs. prod durability. Open WebUI supports both natively. |
| Docker Compose over Kubernetes | Right-sized. Single-server deployment. K8s adds complexity with no benefit at this scale. |
| Nginx over Traefik/Caddy | Explicit config, well-documented, predictable behavior. |
| Root docker-compose.yml + prod override | `docker compose up` works instantly for dev. Prod layers on Nginx + Postgres. |
