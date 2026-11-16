#!/usr/bin/env bash
set -euo pipefail
: "${BACKUP_UPLOAD_SECRET:?Configure BACKUP_UPLOAD_SECRET}"
: "${BACKUP_UPLOAD_URL:?Configure BACKUP_UPLOAD_URL}"
: "${NEON_DUMP_PATH:?Execute backup.sh antes}"
[[ "$BACKUP_UPLOAD_URL" =~ ^https://[a-z0-9.-]+\.workers\.dev$ ]]
test -s "$NEON_DUMP_PATH"
name="neon_$(date -u '+%Y%m%dT%H%M%SZ')_${GITHUB_RUN_ID:-manual}_${GITHUB_RUN_ATTEMPT:-1}.dump"
sha256="$(sha256sum "$NEON_DUMP_PATH" | cut -d ' ' -f 1)"
# Read the secret header via stdin, keeping it out of process arguments.
printf 'Authorization: Bearer %s\n' "$BACKUP_UPLOAD_SECRET" | curl --fail --silent --show-error \
  --max-time 200 --retry 2 --header @- --header "X-Backup-SHA256: $sha256" \
  --header 'Content-Type: application/octet-stream' --upload-file "$NEON_DUMP_PATH" "$BACKUP_UPLOAD_URL/$name"
echo "Backup confirmado em postgresql/$name"
