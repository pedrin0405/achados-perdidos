#!/bin/bash
set -e

BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

echo "=== 1/2 Backup do banco de dados ==="
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  > "$BACKUP_DIR/banco_${TIMESTAMP}.sql"

echo "=== 2/2 Backup das fotos ==="
docker run --rm \
  -v achados-perdidos_fotos:/data:ro \
  -v "$(pwd)/$BACKUP_DIR":/backup \
  alpine tar czf "/backup/fotos_${TIMESTAMP}.tar.gz" -C /data .

echo "=== Backup concluído ==="
ls -lh "$BACKUP_DIR"