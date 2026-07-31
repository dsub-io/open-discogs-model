#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
container_name="open-discogs-model-generator-$$"
catalog_path="$temporary_dir/catalog.tsv"

cleanup() {
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  rm -r "$temporary_dir"
}
trap cleanup EXIT

docker run \
  --detach \
  --rm \
  --name "$container_name" \
  --env POSTGRES_DB=modelgen \
  --env POSTGRES_PASSWORD=modelgen \
  --env POSTGRES_USER=modelgen \
  postgres:18.4-alpine >/dev/null

for attempt in {1..30}; do
  if docker exec "$container_name" \
    psql \
    --username modelgen \
    --dbname modelgen \
    --tuples-only \
    --command 'select 1' >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 30 ]]; then
    echo "PostgreSQL did not become ready" >&2
    exit 1
  fi
  sleep 1
done

while IFS= read -r migration; do
  docker exec \
    --interactive \
    "$container_name" \
    psql \
    --username modelgen \
    --dbname modelgen \
    --set ON_ERROR_STOP=1 < "$migration" >/dev/null
done < <(find "$repository_root/schema/migrations" -type f -name '*.sql' | sort)

docker exec "$container_name" psql \
  --username modelgen \
  --dbname modelgen \
  --no-align \
  --tuples-only \
  --field-separator $'\t' \
  --command "
    select
      columns.table_name,
      columns.column_name,
      columns.data_type,
      columns.udt_name,
      columns.is_nullable,
      coalesce(columns.column_default, ''),
      case when primary_keys.column_name is null then 'false' else 'true' end,
      case when columns.column_default like 'nextval(%' then 'true' else 'false' end
    from information_schema.columns
    left join (
      select
        constraints.table_name,
        keys.column_name
      from information_schema.table_constraints constraints
      join information_schema.key_column_usage keys
        on keys.constraint_schema = constraints.constraint_schema
       and keys.constraint_name = constraints.constraint_name
       and keys.table_name = constraints.table_name
      where constraints.table_schema = 'public'
        and constraints.constraint_type = 'PRIMARY KEY'
    ) primary_keys
      on primary_keys.table_name = columns.table_name
     and primary_keys.column_name = columns.column_name
    where columns.table_schema = 'public'
    order by columns.table_name, columns.ordinal_position
  " > "$catalog_path"

(
  cd "$repository_root"
  go run ./internal/modelgen \
    -input "$catalog_path" \
    -output "$repository_root/model/schema.gen.go"
)
