#!/usr/bin/env bash
# =============================================================================
# medique-hostedui — Initial Setup Script
# =============================================================================
# Usage:
#   ./scripts/setup.sh           # development (default)
#   ./scripts/setup.sh prod      # production
# =============================================================================
set -euo pipefail

ENV="${1:-dev}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

echo "=== medique-hostedui setup ($ENV) ==="
echo ""

# --- Check Docker ---
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed."
    echo "Install it from https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose v2 is required."
    echo "It should be included with Docker Desktop or docker-compose-plugin."
    exit 1
fi

echo "Docker: $(docker --version)"
echo "Compose: $(docker compose version)"
echo ""

# --- Check .env ---
if [ ! -f "$ENV_FILE" ]; then
    echo "No .env file found. Creating from .env.example..."
    cp "$PROJECT_ROOT/.env.example" "$ENV_FILE"
    echo ""
    echo "Created .env — please edit it now:"
    echo "  1. Set OPENAI_API_KEY to your real key"
    if [ "$ENV" = "prod" ]; then
        echo "  2. Set WEBUI_SECRET_KEY (run: openssl rand -hex 32)"
        echo "  3. Set POSTGRES_PASSWORD (run: openssl rand -hex 16)"
        echo "  4. Set ENABLE_SIGNUP=false (or true for first launch only)"
    fi
    echo ""
    echo "Then re-run: ./scripts/setup.sh $ENV"
    exit 0
fi

# --- Validate critical variables ---
source "$ENV_FILE"

if [ "${OPENAI_API_KEY:-}" = "sk-change-me" ] || [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "ERROR: Set OPENAI_API_KEY in .env"
    echo "Get a key at https://platform.openai.com/api-keys"
    exit 1
fi

# Warn if OpenAI API is explicitly disabled (misconfiguration)
if [ "${ENABLE_OPENAI_API:-true}" = "false" ]; then
    echo "WARNING: ENABLE_OPENAI_API is false. OpenAI models will not be available."
    echo "This project requires OpenAI. Set ENABLE_OPENAI_API=true in .env."
    exit 1
fi

# Warn if web search is enabled (violates business rules)
if [ "${ENABLE_RAG_WEB_SEARCH:-false}" = "true" ]; then
    echo "ERROR: ENABLE_RAG_WEB_SEARCH must be false."
    echo "The bot must not search the web — this is a non-negotiable business rule."
    exit 1
fi

if [ "$ENV" = "prod" ]; then
    if [ "${WEBUI_SECRET_KEY:-}" = "dev-only-change-in-prod" ] || [ -z "${WEBUI_SECRET_KEY:-}" ]; then
        echo "ERROR: Set WEBUI_SECRET_KEY in .env for production"
        echo "Generate: openssl rand -hex 32"
        exit 1
    fi

    if [ -z "${POSTGRES_PASSWORD:-}" ] || echo "${POSTGRES_PASSWORD:-}" | grep -q "CHANGE_ME"; then
        echo "ERROR: Set POSTGRES_PASSWORD in .env for production"
        echo "Generate: openssl rand -hex 16"
        exit 1
    fi

    # Check SSL certs
    SSL_DIR="$PROJECT_ROOT/reverse-proxy/ssl"
    if [ ! -f "$SSL_DIR/fullchain.pem" ] || [ ! -f "$SSL_DIR/privkey.pem" ]; then
        echo "ERROR: SSL certificates not found in reverse-proxy/ssl/"
        echo "See docs/deployment.md for Certbot setup instructions."
        exit 1
    fi
fi

# --- Start the stack ---
echo "Starting containers..."
echo ""

if [ "$ENV" = "prod" ]; then
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" \
                   -f "$PROJECT_ROOT/docker-compose.prod.yml" \
                   up -d
else
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" up -d
fi

echo ""

# --- Wait for health ---
echo "Waiting for Open WebUI to become healthy..."
ATTEMPTS=0
MAX_ATTEMPTS=30
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    if docker inspect --format='{{.State.Health.Status}}' medique-webui 2>/dev/null | grep -q healthy; then
        echo "Open WebUI is healthy."
        break
    fi
    ATTEMPTS=$((ATTEMPTS + 1))
    sleep 2
done

if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
    echo "WARNING: Open WebUI did not become healthy within 60 seconds."
    echo "Check logs with: docker compose logs open-webui"
fi

echo ""
echo "=== Setup complete ==="
echo ""

if [ "$ENV" = "prod" ]; then
    echo "Open WebUI: https://${DOMAIN:-yourdomain.com}"
else
    echo "Open WebUI: http://localhost:${WEBUI_PORT:-3000}"
fi

echo ""
echo "Next steps:"
echo "  1. Open the URL above"
echo "  2. Create your admin account (first user = admin)"
echo "  3. Verify OpenAI connection: Admin → Settings → Connections"
echo "  4. Verify models are visible: Admin → Workspace → Models"
echo "  5. Set the system prompt from config/system-prompts/medical-tutor.md"
echo "  6. Configure RAG: Admin → Settings → Documents (chunk 1000, overlap 200)"
echo "  7. Create a Knowledge collection and upload course PDFs"
echo "  8. Bind the collection to gpt-4o-mini"
echo "  9. Disable signup: Admin → Settings → General (or set ENABLE_SIGNUP=false)"
echo " 10. Test with a question from the course material"
echo ""
echo "Full verification checklist: docs/deployment.md"
echo "Secret status: ./scripts/rotate-secrets.sh check"
