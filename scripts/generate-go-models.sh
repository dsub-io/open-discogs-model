#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
container_name="open-discogs-model-generator-$$"
catalog_path="$temporary_dir/catalog.tsv"
postgres_image="postgres:18.4-alpine"
image_was_present=false

cleanup() {
  case "$container_name" in
    open-discogs-model-generator-[0-9]*) ;;
    *)
      printf 'Refusing to clean unexpected container name: %s\n' "$container_name" >&2
      return 1
      ;;
  esac
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  if docker ps -a --filter "name=^/${container_name}$" --format '{{.Names}}' | grep -q .; then
    printf 'Generator container cleanup failed: %s\n' "$container_name" >&2
    return 1
  fi
  if [[ "$image_was_present" == false ]]; then
    docker image rm "$postgres_image" >/dev/null 2>&1 || true
  fi
  rm -r -- "$temporary_dir"
}
trap cleanup EXIT

if docker image inspect "$postgres_image" >/dev/null 2>&1; then
  image_was_present=true
fi

docker run \
  --detach \
  --name "$container_name" \
  --label io.dsub.test-owner=open-discogs-model \
  --tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=512m \
  --env POSTGRES_DB=modelgen \
  --env POSTGRES_PASSWORD=modelgen \
  --env POSTGRES_USER=modelgen \
  "$postgres_image" >/dev/null

volume_mounts="$(
  docker inspect \
    --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
    "$container_name"
)"
if [[ -n "$volume_mounts" ]]; then
  printf 'Generator unexpectedly created Docker volumes: %s\n' "$volume_mounts" >&2
  exit 1
fi

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
