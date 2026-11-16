#!/usr/bin/env bash
set -euo pipefail
: "${NEON_BACKUP_URL:?Configure NEON_BACKUP_URL}"
: "${RUNNER_TEMP:?Defina RUNNER_TEMP}"
image=postgres:18
dir="$(mktemp -d "$RUNNER_TEMP/neon-backup.XXXXXXXX")"
container="tech2d-check-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT

# Pass only connection settings as environment, never in the command arguments.
mapfile -t settings < <(python3 - <<'PY'
import os
from urllib.parse import urlsplit, unquote
u = urlsplit(os.environ['NEON_BACKUP_URL'])
assert u.scheme in ('postgres', 'postgresql')
assert u.hostname and u.hostname.endswith('.neon.tech') and '-pooler.' not in u.hostname
assert u.username == 'tech2d_backup' and u.password and u.path != '/'
for value in (u.hostname, str(u.port or 5432), unquote(u.username), unquote(u.password), unquote(u.path[1:])):
    assert '\n' not in value and '\r' not in value
    print(value)
PY
)
[[ ${#settings[@]} == 5 ]] || { echo 'Conexão direta de backup inválida'; exit 1; }
export PGHOST="${settings[0]}" PGPORT="${settings[1]}" PGUSER="${settings[2]}" PGPASSWORD="${settings[3]}" PGDATABASE="${settings[4]}"
export PGSSLMODE=verify-full PGSSLROOTCERT=/backup-ca.pem PGCONNECT_TIMEOUT=20
unset NEON_BACKUP_URL settings
if ! docker run --rm --user "$(id -u):$(id -g)" \
  -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE -e PGSSLROOTCERT -e PGCONNECT_TIMEOUT \
  -v /etc/ssl/certs/ca-certificates.crt:/backup-ca.pem:ro \
  -v "$dir:/backup" "$image" pg_dump --no-password --format=custom --schema=tech2d \
  --enable-row-security --no-owner --no-acl --file=/backup/neon.dump 2>"$dir/pg_dump.err"; then
  echo 'Falha ao gerar o dump. Confira acesso, TLS e permissões da conexão de backup.'
  exit 1
fi
unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE PGSSLMODE PGSSLROOTCERT PGCONNECT_TIMEOUT
test -s "$dir/neon.dump"

docker run -d --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust "$image" >/dev/null
for attempt in {1..60}; do
  if docker exec "$container" pg_isready --host=127.0.0.1 --username=postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
docker exec "$container" psql -X --host=127.0.0.1 --username=postgres --set=ON_ERROR_STOP=1 --quiet \
  -c 'CREATE ROLE tech2d_backup NOLOGIN; CREATE ROLE tech2d_api NOLOGIN;'
if ! docker exec -i "$container" pg_restore --host=127.0.0.1 --username=postgres --dbname=postgres --no-owner --no-acl \
  --exit-on-error --single-transaction < "$dir/neon.dump" 2>"$dir/pg_restore.err"; then
  echo 'O dump falhou no teste de restauração descartável.'
  exit 1
fi
docker exec -i "$container" psql -X --host=127.0.0.1 --username=postgres --set=ON_ERROR_STOP=1 --quiet <<'SQL'
DO $$
BEGIN
  IF (SELECT count(*) FROM tech2d.atividades) = 0
     OR (SELECT count(*) FROM tech2d.horarios_aula) = 0 THEN
    RAISE EXCEPTION 'O dump restaurado não contém as atividades ou os horários';
  END IF;
END $$;
SQL
echo 'Dump restaurado e conferido em PostgreSQL descartável.'
printf 'NEON_DUMP_PATH=%s\n' "$dir/neon.dump" >>"${GITHUB_ENV:?Defina GITHUB_ENV}"
