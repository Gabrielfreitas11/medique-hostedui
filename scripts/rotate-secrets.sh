#!/usr/bin/env bash
# =============================================================================
# medique-hostedui — Secret Rotation Helper
# =============================================================================
# Usage:
#   ./scripts/rotate-secrets.sh openai      # rotate OPENAI_API_KEY
#   ./scripts/rotate-secrets.sh webui       # rotate WEBUI_SECRET_KEY
#   ./scripts/rotate-secrets.sh postgres    # rotate POSTGRES_PASSWORD
#   ./scripts/rotate-secrets.sh check       # check secret age
#
# This script GUIDES you through rotation — it does not generate or store
# secrets automatically. You still need to:
#   - Create a new OpenAI key at https://platform.openai.com/api-keys
#   - Edit .env manually to paste the new value
#   - Revoke the old key after verifying the new one works
#
# Full rotation procedures: docs/security.md
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
COMPOSE_CMD="docker compose"

# Detect if prod compose files should be used
is_prod() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q medique-postgres
}

compose_cmd() {
    if is_prod; then
        $COMPOSE_CMD -f "$PROJECT_ROOT/docker-compose.yml" \
                     -f "$PROJECT_ROOT/docker-compose.prod.yml" \
                     "$@"
    else
        $COMPOSE_CMD -f "$PROJECT_ROOT/docker-compose.yml" "$@"
    fi
}

check_env() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "ERROR: .env file not found at $ENV_FILE"
        exit 1
    fi
}

# --- Commands ---

rotate_openai() {
    check_env
    echo "=== Rotate OPENAI_API_KEY ==="
    echo ""
    echo "Step 1: Create a new API key"
    echo "   → https://platform.openai.com/api-keys"
    echo "   → Name it with today's date: medique-$(date +%Y-%m-%d)"
    echo ""
    read -p "Have you created the new key? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    echo "Step 2: Edit .env and replace the OPENAI_API_KEY value"
    echo "   → File: $ENV_FILE"
    echo ""
    read -p "Have you updated .env with the new key? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    echo "Step 3: Restarting Open WebUI..."
    compose_cmd restart open-webui

    echo ""
    echo "Step 4: Waiting for health check..."
    sleep 5
    if docker inspect --format='{{.State.Health.Status}}' medique-webui 2>/dev/null | grep -q healthy; then
        echo "Open WebUI is healthy."
    else
        echo "WARNING: Health check not yet passing. Check logs:"
        echo "   docker compose logs --tail 20 open-webui"
    fi

    echo ""
    echo "Step 5: Verify the connection"
    echo "   → Open Admin → Settings → Connections"
    echo "   → Confirm OpenAI shows green/connected"
    echo ""
    echo "Step 6: After confirming, REVOKE the old key"
    echo "   → https://platform.openai.com/api-keys"
    echo ""
    echo "=== Done ==="
}

rotate_webui() {
    check_env
    echo "=== Rotate WEBUI_SECRET_KEY ==="
    echo ""
    echo "WARNING: This will log out ALL users (including admin)."
    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    NEW_SECRET=$(openssl rand -hex 32)
    echo ""
    echo "Generated new secret: $NEW_SECRET"
    echo ""
    echo "Step 1: Edit .env and set WEBUI_SECRET_KEY to the value above"
    echo "   → File: $ENV_FILE"
    echo ""
    read -p "Have you updated .env? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. (The generated secret was not saved anywhere.)"
        exit 0
    fi

    echo ""
    echo "Step 2: Restarting Open WebUI..."
    compose_cmd restart open-webui

    echo ""
    echo "All user sessions have been invalidated."
    echo "Everyone (including you) must log in again."
    echo ""
    echo "=== Done ==="
}

rotate_postgres() {
    check_env

    if ! is_prod; then
        echo "ERROR: PostgreSQL rotation only applies to production."
        echo "Development uses SQLite (no password)."
        exit 1
    fi

    echo "=== Rotate POSTGRES_PASSWORD ==="
    echo ""

    NEW_PASSWORD=$(openssl rand -hex 16)
    echo "Generated new password: $NEW_PASSWORD"
    echo ""
    echo "This is a 3-step process. Order matters."
    echo ""
    echo "Step 1: Change the password inside PostgreSQL"
    echo "   Running: ALTER USER ... PASSWORD ..."

    # Source .env to get current POSTGRES_USER
    source "$ENV_FILE"
    PG_USER="${POSTGRES_USER:-medique}"

    docker exec medique-postgres psql -U "$PG_USER" -c "ALTER USER $PG_USER PASSWORD '$NEW_PASSWORD';"

    echo "   PostgreSQL password updated."
    echo ""
    echo "Step 2: Update .env with the new POSTGRES_PASSWORD"
    echo "   New value: $NEW_PASSWORD"
    echo "   → File: $ENV_FILE"
    echo ""
    read -p "Have you updated .env? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "WARNING: PostgreSQL has the new password but .env has the old one."
        echo "Open WebUI will fail to connect on next restart."
        echo "Update .env NOW with: $NEW_PASSWORD"
        exit 1
    fi

    echo ""
    echo "Step 3: Restarting Open WebUI to use the new password..."
    compose_cmd restart open-webui

    sleep 5
    if docker inspect --format='{{.State.Health.Status}}' medique-webui 2>/dev/null | grep -q healthy; then
        echo "Open WebUI is healthy. Rotation complete."
    else
        echo "WARNING: Health check not passing. Check logs:"
        echo "   docker compose logs --tail 20 open-webui"
    fi
    echo ""
    echo "=== Done ==="
}

check_secrets() {
    check_env
    echo "=== Secret Status ==="
    echo ""

    # .env modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        MOD_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$ENV_FILE")
    else
        MOD_DATE=$(stat -c "%y" "$ENV_FILE" | cut -d. -f1)
    fi
    echo ".env last modified: $MOD_DATE"
    echo ""

    source "$ENV_FILE"

    # Check OPENAI_API_KEY
    KEY="${OPENAI_API_KEY:-}"
    if [ -z "$KEY" ] || [ "$KEY" = "sk-change-me" ]; then
        echo "OPENAI_API_KEY:    NOT SET (placeholder)"
    else
        MASKED="${KEY:0:7}...${KEY: -4}"
        echo "OPENAI_API_KEY:    $MASKED"
    fi

    # Check WEBUI_SECRET_KEY
    SECRET="${WEBUI_SECRET_KEY:-}"
    if [ -z "$SECRET" ] || [ "$SECRET" = "dev-only-change-in-prod" ]; then
        echo "WEBUI_SECRET_KEY:  DEV DEFAULT (not suitable for production)"
    else
        echo "WEBUI_SECRET_KEY:  set (${#SECRET} chars)"
    fi

    # Check POSTGRES_PASSWORD
    PGPASS="${POSTGRES_PASSWORD:-}"
    if [ -z "$PGPASS" ]; then
        echo "POSTGRES_PASSWORD: not set (OK for dev, required for prod)"
    else
        echo "POSTGRES_PASSWORD: set (${#PGPASS} chars)"
    fi

    echo ""
    echo "Recommendation: rotate all secrets every 90 days."
    echo "Full procedures: docs/security.md"
}

# --- Main ---

case "${1:-help}" in
    openai)   rotate_openai ;;
    webui)    rotate_webui ;;
    postgres) rotate_postgres ;;
    check)    check_secrets ;;
    *)
        echo "Usage: $0 {openai|webui|postgres|check}"
        echo ""
        echo "  openai    — rotate OPENAI_API_KEY"
        echo "  webui     — rotate WEBUI_SECRET_KEY (logs out all users)"
        echo "  postgres  — rotate POSTGRES_PASSWORD (production only)"
        echo "  check     — show current secret status"
        exit 1
        ;;
esac
