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

for version in $(seq -f '%03g' 9 23); do
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

exact_lookup_indexes="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command "
    select indexname
    from pg_indexes
    where schemaname = 'public'
      and indexname in (
        'ix_label_release_item_label_catalog_release',
        'ix_release_item_identifier_type_value_release'
      )
    order by indexname
  ")"
expected_exact_lookup_indexes="$(printf '%s\n' \
  'ix_label_release_item_label_catalog_release' \
  'ix_release_item_identifier_type_value_release')"
if [[ "$exact_lookup_indexes" != "$expected_exact_lookup_indexes" ]]; then
  printf 'Unexpected exact lookup index inventory:\n%s\n' \
    "$exact_lookup_indexes" >&2
  exit 1
fi

non_release_identity_inventory="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only --field-separator '|' \
  --command "
    select count(*),
           count(identity_check.oid),
           count(identity_check.oid) filter (where not identity_check.convalidated),
           count(legacy_unique.oid)
    from (values
      ('artist_name_variation', 'uq_artist_name_variation_artist_id_hash',
       'ck_artist_name_variation_identity_sha256_length'),
      ('artist_url', 'uq_artist_url_artist_id_hash',
       'ck_artist_url_identity_sha256_length'),
      ('label_url', 'uq_label_url_label_id_hash',
       'ck_label_url_identity_sha256_length'),
      ('master_video', 'uq_master_video_master_id_hash',
       'ck_master_video_identity_sha256_length')
    ) expected(table_name, unique_name, check_name)
    join information_schema.columns identity_column
      on identity_column.table_schema = 'public'
     and identity_column.table_name = expected.table_name
     and identity_column.column_name = 'identity_sha256'
     and identity_column.data_type = 'bytea'
     and identity_column.is_nullable = 'YES'
    left join pg_constraint identity_check
      on identity_check.conrelid = to_regclass(
           format('public.%I', expected.table_name)
         )
     and identity_check.conname = expected.check_name
     and identity_check.contype = 'c'
    left join pg_constraint legacy_unique
      on legacy_unique.conrelid = to_regclass(
           format('public.%I', expected.table_name)
         )
     and legacy_unique.conname = expected.unique_name
     and legacy_unique.contype = 'u'
  ")"
if [[ "$non_release_identity_inventory" != '4|4|4|4' ]]; then
  printf 'Unexpected non-release identity inventory: %s\n' \
    "$non_release_identity_inventory" >&2
  exit 1
fi

non_release_hash_tables="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command "
    select table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'hash'
      and table_name not like 'release_item_%'
    order by table_name
  ")"
expected_non_release_hash_tables="$(printf '%s\n' \
  'artist_name_variation' \
  'artist_url' \
  'label_url' \
  'master_video')"
if [[ "$non_release_hash_tables" != "$expected_non_release_hash_tables" ]]; then
  printf 'Unexpected non-release hash relation inventory:\n%s\n' \
    "$non_release_hash_tables" >&2
  exit 1
fi

non_release_identity_indexes="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command "
    select count(*)
    from pg_indexes
    where schemaname = 'public'
      and tablename in (
        'artist_name_variation', 'artist_url', 'label_url', 'master_video'
      )
      and indexdef like '%identity_sha256%'
  ")"
if [[ "$non_release_identity_indexes" != '0' ]]; then
  printf 'V021 created %s identity indexes; expected metadata-only columns\n' \
    "$non_release_identity_indexes" >&2
  exit 1
fi

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.artist (id, created_at, last_modified_at)
    values (33476, now(), now());
    insert into public.artist_name_variation (
      hash, identity_sha256, last_modified_at, name_variation, artist_id
    ) values
      (2112,
       decode('fb6210e9ce991c5e2e8eefd55acfc5c5b7afbd73cf626787a8fd2f57517039ff', 'hex'),
       now(), 'BB', 33476),
      (-851983164,
       decode('9ea73f5c741d87f3051cb2a720c3123d0d4897ae48b2c0ae6d9bdcd88ff1afee', 'hex'),
       now(), 'Aa', 33476);
  " >/dev/null

collision_row_count="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command '
    select count(distinct identity_sha256)
    from public.artist_name_variation
    where artist_id = 33476
  ')"
if [[ "$collision_row_count" != '2' ]]; then
  printf 'Collision-safe artist relation retained %s identities; expected 2\n' \
    "$collision_row_count" >&2
  exit 1
fi

relation_id_columns="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command "
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'id'
      and table_name in (
        'release_item_genre', 'release_item_track', 'label_release_item',
        'release_item_image', 'release_item_work', 'release_item_identifier',
        'master_video', 'master_genre', 'master_style', 'release_item_style',
        'label_sub_label', 'release_item_video', 'label_url',
        'release_item_format', 'artist_alias', 'artist_name_variation',
        'master_artist', 'release_item_artist',
        'release_item_credited_artist', 'artist_url', 'artist_group',
        'artist_member'
      )
  ")"
if [[ "$relation_id_columns" != '0' ]]; then
  printf 'Relation tables retained %s surrogate ID columns\n' "$relation_id_columns" >&2
  exit 1
fi

bootstrap_constraint_inventory="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only --field-separator '|' \
  --command "
    select count(*),
           count(constraint_state.oid),
           count(constraint_state.oid)
               filter (where constraint_state.convalidated)
    from public.discogs_bootstrap_foreign_keys() foreign_key
    left join pg_constraint constraint_state
      on constraint_state.conrelid = to_regclass(
           format('public.%I', foreign_key.table_name)
         )
     and constraint_state.conname = foreign_key.constraint_name
  ")"
if [[ "$bootstrap_constraint_inventory" != '37|37|37' ]]; then
  printf 'Unexpected bootstrap foreign-key inventory: %s\n' \
    "$bootstrap_constraint_inventory" >&2
  exit 1
fi

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.discogs_import_run (
      manifest_sha256, status, processor, processor_version
    ) values (repeat('b', 64), 'running', 'migration-test', '1');
    update public.discogs_catalog_entity_state
    set status = 'importing',
        operation = 'bootstrap',
        active_import_run_id = currval('discogs_import_run_id_seq')
    where entity_type = 'artist';
    select public.prepare_discogs_bootstrap_foreign_keys(
      currval('discogs_import_run_id_seq')
    );
  " >/dev/null

artist_bootstrap_constraints="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command "
    select count(constraint_state.oid)
    from public.discogs_bootstrap_foreign_keys() foreign_key
    left join pg_constraint constraint_state
      on constraint_state.conrelid = to_regclass(
           format('public.%I', foreign_key.table_name)
         )
     and constraint_state.conname = foreign_key.constraint_name
    where foreign_key.entity_type = 'artist'
  ")"
if [[ "$artist_bootstrap_constraints" != '0' ]]; then
  printf 'Bootstrap retained %s artist foreign keys; expected 0\n' \
    "$artist_bootstrap_constraints" >&2
  exit 1
fi

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    insert into public.artist_alias (alias_id, artist_id, last_modified_at)
    values (990, 991, now());
  " >/dev/null

if docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    select public.finalize_discogs_bootstrap(
      (select id from public.discogs_import_run
       where manifest_sha256 = repeat('b', 64))
    );
  " >/dev/null 2>&1; then
  printf 'Bootstrap finalization accepted an invalid artist relation\n' >&2
  exit 1
fi

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    delete from public.artist_alias where artist_id = 991;
    select public.finalize_discogs_bootstrap(
      (select id from public.discogs_import_run
       where manifest_sha256 = repeat('b', 64))
    );
  " >/dev/null

validated_artist_constraints="$(docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --no-align --tuples-only \
  --command "
    select count(*)
    from public.discogs_bootstrap_foreign_keys() foreign_key
    join pg_constraint constraint_state
      on constraint_state.conrelid = to_regclass(
           format('public.%I', foreign_key.table_name)
         )
     and constraint_state.conname = foreign_key.constraint_name
     and constraint_state.convalidated
    where foreign_key.entity_type = 'artist'
  ")"
if [[ "$validated_artist_constraints" != '8' ]]; then
  printf 'Bootstrap validated %s artist foreign keys; expected 8\n' \
    "$validated_artist_constraints" >&2
  exit 1
fi

docker exec "$container_name" \
  psql --username migrationtest --dbname migrationtest \
  --set ON_ERROR_STOP=1 --command "
    update public.discogs_catalog_entity_state
    set status = 'bootstrap_pending',
        operation = 'bootstrap',
        active_import_run_id = null
    where entity_type = 'artist';
    update public.discogs_import_run
    set status = 'failed', completed_at = now(), failure_message = 'fixture'
    where manifest_sha256 = repeat('b', 64);
  " >/dev/null

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
