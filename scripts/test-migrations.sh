#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container_name="open-discogs-model-migration-test-$$"
postgres_image="postgres:18.4-alpine"
image_was_present=false

cleanup() {
  case "$container_name" in
    open-discogs-model-migration-test-[0-9]*) ;;
    *)
      printf 'Refusing to clean unexpected container name: %s\n' "$container_name" >&2
      return 1
      ;;
  esac
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  if docker ps -a --filter "name=^/${container_name}$" --format '{{.Names}}' | grep -q .; then
    printf 'Migration test container cleanup failed: %s\n' "$container_name" >&2
    return 1
  fi
  if [[ "$image_was_present" == false ]]; then
    docker image rm "$postgres_image" >/dev/null 2>&1 || true
  fi
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
  --env POSTGRES_DB=migrationtest \
  --env POSTGRES_PASSWORD=migrationtest \
  --env POSTGRES_USER=migrationtest \
  "$postgres_image" >/dev/null

volume_mounts="$(
  docker inspect \
    --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
    "$container_name"
)"
if [[ -n "$volume_mounts" ]]; then
  printf 'Migration test unexpectedly created Docker volumes: %s\n' "$volume_mounts" >&2
  exit 1
fi

for attempt in {1..30}; do
  if docker exec "$container_name" \
    psql --username migrationtest --dbname migrationtest \
    --tuples-only --command 'select 1' >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 30 ]]; then
    printf 'PostgreSQL did not become ready\n' >&2
    exit 1
  fi
  sleep 1
done

for version in 001 002 003 004 005 006 007; do
  migration="$(find "$repository_root/schema/migrations" \
    -maxdepth 1 -type f -name "V${version}__*.sql" -print -quit)"
  if [[ -z "$migration" ]]; then
    printf 'Missing migration V%s\n' "$version" >&2
    exit 1
  fi
  docker exec --interactive "$container_name" \
    psql --username migrationtest --dbname migrationtest \
    --set ON_ERROR_STOP=1 < "$migration" >/dev/null
done

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.label (id, created_at, last_modified_at)
    values (5, now(), now());
    insert into public.release_item (id, created_at, last_modified_at)
    values (2, now(), now());
    insert into public.label_release_item (
      created_at, last_modified_at, category_notation, label_id, release_item_id
    ) values (now(), now(), 'SK026', 5, 2);
  " >/dev/null

docker exec --interactive "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 \
  < "$repository_root/schema/migrations/V008__label_release_catalog_identity.sql" \
  >/dev/null

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.label_release_item (
      created_at, last_modified_at, category_notation, label_id, release_item_id
    ) values
      (now(), now(), 'SK 026', 5, 2),
      (now(), now(), null, 5, 2);
  " >/dev/null

if docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.label_release_item (
      created_at, last_modified_at, category_notation, label_id, release_item_id
    ) values (now(), now(), 'SK026', 5, 2);
  " >/dev/null 2>&1; then
  printf 'Duplicate catalog identity was accepted\n' >&2
  exit 1
fi

if docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.label_release_item (
      created_at, last_modified_at, category_notation, label_id, release_item_id
    ) values (now(), now(), null, 5, 2);
  " >/dev/null 2>&1; then
  printf 'Duplicate NULL catalog identity was accepted\n' >&2
  exit 1
fi

row_count="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command 'select count(*) from public.label_release_item')"
if [[ "$row_count" != 3 ]]; then
  printf 'Label release migration retained %s rows; expected 3\n' "$row_count" >&2
  exit 1
fi

for version in $(seq -f '%03g' 9 18); do
  migration="$(find "$repository_root/schema/migrations" \
    -maxdepth 1 -type f -name "V${version}__*.sql" -print -quit)"
  if [[ -z "$migration" ]]; then
    printf 'Missing migration V%s\n' "$version" >&2
    exit 1
  fi
  docker exec --interactive "$container_name" \
    psql --username migrationtest --dbname migrationtest \
    --set ON_ERROR_STOP=1 < "$migration" >/dev/null
done

entity_state="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only --field-separator '|' \
  --command '
    select entity_type, status, operation
    from public.discogs_catalog_entity_state
    order by entity_type
  ')"
expected_entity_state="$(printf '%s\n' \
  'artist|bootstrap_pending|bootstrap' \
  'label|bootstrap_pending|bootstrap' \
  'master|bootstrap_pending|bootstrap' \
  'release|bootstrap_pending|bootstrap')"
if [[ "$entity_state" != "$expected_entity_state" ]]; then
  printf 'Unexpected initial catalog state:\n%s\n' "$entity_state" >&2
  exit 1
fi

readiness="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only --field-separator '|' \
  --command '
    select ready, status, ready_entities, required_entities
    from public.discogs_catalog_readiness
  ')"
if [[ "$readiness" != 'f|bootstrap_pending|0|4' ]]; then
  printf 'Unexpected initial catalog readiness: %s\n' "$readiness" >&2
  exit 1
fi

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    drop view public.discogs_catalog_readiness;
    drop table public.discogs_catalog_entity_state;

    insert into public.discogs_dump (
      created_at, last_modified_at, etag, dump_date, entity_type,
      checksum_sha256, size_bytes, uri
    )
    select
      now(), now(), 'etag-' || entity_type, date '2026-08-01', entity_type,
      repeat('a', 64), 1, entity_type || '.xml.gz'
    from (values ('artist'), ('label'), ('master'), ('release')) entity(entity_type);

    insert into public.discogs_import_run (
      completed_at, manifest_sha256, status, processor, processor_version
    ) values (now(), repeat('a', 64), 'success', 'fixture', '1');

    insert into public.discogs_import_run_dump (
      import_run_id, entity_type, dump_id, import_contract_revision
    )
    select currval('discogs_import_run_id_seq'), entity_type, id, 1
    from public.discogs_dump;
  " >/dev/null

docker exec --interactive "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 \
  < "$repository_root/schema/migrations/V018__catalog_readiness_state.sql" \
  >/dev/null

adopted_readiness="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only --field-separator '|' \
  --command '
    select ready, status, ready_entities, required_entities
    from public.discogs_catalog_readiness
  ')"
if [[ "$adopted_readiness" != 't|ready|4|4' ]]; then
  printf 'Unexpected adopted catalog readiness: %s\n' "$adopted_readiness" >&2
  exit 1
fi
