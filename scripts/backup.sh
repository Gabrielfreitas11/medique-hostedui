#!/usr/bin/env bash
# =============================================================================
# medique-hostedui — Backup Script
# =============================================================================
# Usage:
#   ./scripts/backup.sh                    # backups to ./backups/
#   ./scripts/backup.sh /path/to/storage   # backups to custom directory
#
# Creates a timestamped directory with:
#   - postgres.sql.gz    (PostgreSQL dump, if running)
#   - webui-data.tar.gz  (Open WebUI data volume)
#
# See docs/operations.md for restore procedures.
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="${1:-$PROJECT_ROOT/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$BACKUP_PATH"

echo "=== medique-hostedui backup ==="
echo "Destination: $BACKUP_PATH"
echo ""

ERRORS=0

# --- PostgreSQL dump (if container is running) ---
if docker ps --format '{{.Names}}' | grep -q medique-postgres; then
    echo "Backing up PostgreSQL..."
    if docker exec medique-postgres pg_dump -U "${POSTGRES_USER:-medique}" "${POSTGRES_DB:-medique}" \
        | gzip > "$BACKUP_PATH/postgres.sql.gz"; then
        SIZE=$(du -h "$BACKUP_PATH/postgres.sql.gz" | cut -f1)
        echo "  ✓ postgres.sql.gz ($SIZE)"
    else
        echo "  ✗ PostgreSQL backup failed"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "PostgreSQL container not running — skipping database dump."
    echo "  (This is normal for development, which uses SQLite inside the webui-data volume.)"
fi

# --- Open WebUI data volume ---
if docker volume ls --format '{{.Name}}' | grep -q medique-webui-data; then
    echo "Backing up Open WebUI data volume..."
    if docker run --rm \
        -v medique-webui-data:/data:ro \
        -v "$BACKUP_PATH":/backup \
        alpine tar czf /backup/webui-data.tar.gz -C /data .; then
        SIZE=$(du -h "$BACKUP_PATH/webui-data.tar.gz" | cut -f1)
        echo "  ✓ webui-data.tar.gz ($SIZE)"
    else
        echo "  ✗ Open WebUI data backup failed"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  ✗ Volume medique-webui-data not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""

if [ $ERRORS -gt 0 ]; then
    echo "=== Backup completed with $ERRORS error(s) ==="
    exit 1
else
    echo "=== Backup complete: $BACKUP_PATH ==="
fi
