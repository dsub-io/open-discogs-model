#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_owner="open-discogs-model"
test_suite="release-convergence-contract"
test_run="$(date -u +%Y%m%dT%H%M%SZ)-$$"
postgres_images=("postgres:15.13-alpine" "postgres:18.4-alpine")
container_names=()
created_volume_names=()

cleanup() {
  local cleanup_status=0
  local container_name
  local actual_owner
  local actual_suite
  local actual_run
  local resource_ids
  local volume_name

  for container_name in ${container_names[@]+"${container_names[@]}"}; do
    if ! docker container inspect "$container_name" >/dev/null 2>&1; then
      continue
    fi
    actual_owner="$(docker container inspect \
      --format '{{index .Config.Labels "io.dsub.test-owner"}}' "$container_name")"
    actual_suite="$(docker container inspect \
      --format '{{index .Config.Labels "io.dsub.test-suite"}}' "$container_name")"
    actual_run="$(docker container inspect \
      --format '{{index .Config.Labels "io.dsub.test-run"}}' "$container_name")"
    if [[ "$actual_owner" != "$test_owner" \
      || "$actual_suite" != "$test_suite" \
      || "$actual_run" != "$test_run" ]]; then
      printf 'Refusing to clean container with unexpected ownership: %s\n' \
        "$container_name" >&2
      cleanup_status=1
      continue
    fi
    docker container rm --force --volumes "$container_name" >/dev/null \
      || cleanup_status=1
  done

  for volume_name in ${created_volume_names[@]+"${created_volume_names[@]}"}; do
    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
      docker volume rm "$volume_name" >/dev/null || cleanup_status=1
    fi
  done

  resource_ids="$(docker container ls --all --quiet \
    --filter "label=io.dsub.test-owner=$test_owner" \
    --filter "label=io.dsub.test-suite=$test_suite" \
    --filter "label=io.dsub.test-run=$test_run")"
  if [[ -n "$resource_ids" ]]; then
    printf 'Docker container residue remains for test run %s: %s\n' \
      "$test_run" "$resource_ids" >&2
    cleanup_status=1
  fi

  for resource_type in network volume; do
    resource_ids="$(docker "$resource_type" ls --quiet \
      --filter "label=io.dsub.test-owner=$test_owner" \
      --filter "label=io.dsub.test-suite=$test_suite" \
      --filter "label=io.dsub.test-run=$test_run")"
    if [[ -n "$resource_ids" ]]; then
      printf 'Docker %s residue remains for test run %s: %s\n' \
        "$resource_type" "$test_run" "$resource_ids" >&2
      cleanup_status=1
    fi
  done

  return "$cleanup_status"
}

on_exit() {
  local test_status=$?
  trap - EXIT HUP INT TERM
  if ! cleanup; then
    test_status=1
  fi
  if [[ "$test_status" == 0 ]]; then
    printf 'Docker cleanup and residue verification passed for %s\n' "$test_run"
  fi
  exit "$test_status"
}

trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_postgres() {
  local container_name=$1

  # The temporary init server accepts SQL before the entrypoint starts the final PID 1 server.
  for _ in {1..60}; do
    if docker exec "$container_name" sh -ceu '
      test "$(cat /proc/1/comm)" = postgres
      exec psql --username postgres --dbname postgres \
        --no-psqlrc --tuples-only --command "select 1"
    ' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  printf 'PostgreSQL did not become ready: %s\n' "$container_name" >&2
  return 1
}

apply_migrations_through_v008() {
  local container_name=$1
  local database_name=$2
  local version
  local migration

  for version in 001 002 003 004 005 006 007 008; do
    migration="$(find "$repository_root/schema/migrations" \
      -maxdepth 1 -type f -name "V${version}__*.sql" -print -quit)"
    if [[ -z "$migration" ]]; then
      printf 'Missing migration V%s\n' "$version" >&2
      return 1
    fi
    docker exec --interactive "$container_name" \
      psql --username postgres --dbname "$database_name" \
      --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction \
      < "$migration" >/dev/null
  done
}

apply_v009() {
  local container_name=$1
  local database_name=$2

  docker exec --interactive "$container_name" \
    psql --username postgres --dbname "$database_name" \
    --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction \
    < "$repository_root/schema/migrations/V009__release_convergence_contract.sql" \
    >/dev/null
}

apply_release_identity_migrations() {
  local container_name=$1
  local database_name=$2
  local version
  local migration

  for version in 010 011 012 013 014 015 016; do
    migration="$(find "$repository_root/schema/migrations" \
      -maxdepth 1 -type f -name "V${version}__*.sql" -print -quit)"
    if [[ -z "$migration" ]]; then
      printf 'Missing migration V%s\n' "$version" >&2
      return 1
    fi
    docker exec --interactive "$container_name" \
      psql --username postgres --dbname "$database_name" \
      --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction \
      < "$migration" >/dev/null
  done
}

execute_sql() {
  local container_name=$1
  local database_name=$2
  local statement=$3

  docker exec "$container_name" \
    psql --username postgres --dbname "$database_name" \
    --no-psqlrc --set ON_ERROR_STOP=1 --command "$statement" >/dev/null
}

assert_scalar() {
  local container_name=$1
  local database_name=$2
  local query=$3
  local expected=$4
  local actual

  actual="$(docker exec "$container_name" \
    psql --username postgres --dbname "$database_name" \
    --no-psqlrc --no-align --tuples-only --set ON_ERROR_STOP=1 \
    --command "$query")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Unexpected query result in %s: expected %s, got %s\n' \
      "$database_name" "$expected" "$actual" >&2
    return 1
  fi
}

relation_heap_nodes() {
  local container_name=$1
  local database_name=$2

  docker exec "$container_name" \
    psql --username postgres --dbname "$database_name" \
    --no-psqlrc --no-align --tuples-only --set ON_ERROR_STOP=1 \
    --command "
      select string_agg(relname || ':' || relfilenode::text, ',' order by relname)
      from pg_class
      where oid in (
        'public.release_item_credited_artist'::regclass,
        'public.release_item_format'::regclass,
        'public.release_item_identifier'::regclass,
        'public.release_item_image'::regclass,
        'public.release_item_track'::regclass,
        'public.release_item_video'::regclass,
        'public.release_item_work'::regclass
      );"
}

expect_sql_failure() {
  local container_name=$1
  local database_name=$2
  local statement=$3

  if docker exec "$container_name" \
    psql --username postgres --dbname "$database_name" \
    --no-psqlrc --set ON_ERROR_STOP=1 --command "$statement" \
    >/dev/null 2>&1; then
    printf 'Statement unexpectedly succeeded in %s: %s\n' \
      "$database_name" "$statement" >&2
    return 1
  fi
}

seed_import_run() {
  local container_name=$1
  local database_name=$2

  execute_sql "$container_name" "$database_name" "
    insert into public.discogs_dump (
      etag,
      dump_date,
      entity_type,
      checksum_sha256,
      size_bytes,
      uri
    ) values
      ('artist-etag', date '2026-08-01', 'artist', repeat('1', 64), 1, '/artist'),
      ('label-etag', date '2026-08-01', 'label', repeat('2', 64), 1, '/label'),
      ('master-etag', date '2026-08-01', 'master', repeat('3', 64), 1, '/master'),
      ('release-etag', date '2026-08-01', 'release', repeat('4', 64), 1, '/release');

    with legacy_run as (
      insert into public.discogs_import_run (
        completed_at,
        manifest_sha256,
        status,
        processor,
        processor_version
      ) values (
        now(),
        repeat('a', 64),
        'success',
        'legacy-consumer',
        '1.0.0'
      )
      returning id
    )
    insert into public.discogs_import_run_dump (
      import_run_id,
      entity_type,
      dump_id
    )
    select legacy_run.id, discogs_dump.entity_type, discogs_dump.id
    from legacy_run
    cross join public.discogs_dump;
  "
}

seed_valid_release_relationships() {
  local container_name=$1
  local database_name=$2

  execute_sql "$container_name" "$database_name" "
    insert into public.artist (id, created_at, last_modified_at)
    values (10, now(), now());
    insert into public.label (id, created_at, last_modified_at)
    values (20, now(), now());
    insert into public.master (id, created_at, last_modified_at)
    values (1, now(), now()), (2, now(), now());
    insert into public.release_item (
      id, created_at, last_modified_at, master_id
    ) values
      (101, now(), now(), 1),
      (102, now(), now(), 2);
    update public.master
    set main_release_id = case id when 1 then 101 when 2 then 102 end
    where id in (1, 2);

    insert into public.release_item_credited_artist (
      id, created_at, last_modified_at, hash, role, artist_id, release_item_id
    ) values (1001, now(), now(), 1, 'Producer', 10, 101);
    insert into public.release_item_format (
      id, created_at, last_modified_at, hash, name, quantity, release_item_id
    ) values (1002, now(), now(), 2, 'CD', 1, 101);
    insert into public.release_item_identifier (
      id, created_at, last_modified_at, hash, type, value, release_item_id
    ) values (1003, now(), now(), 3, 'Barcode', '123', 101);
    insert into public.release_item_image (
      id, created_at, last_modified_at, hash, file_name, release_item_id
    ) values (1007, now(), now(), 7, 'cover.jpg', 101);
    insert into public.release_item_track (
      id, created_at, last_modified_at, hash, position, title, release_item_id
    ) values (1004, now(), now(), 4, '1', 'Track', 101);
    insert into public.release_item_video (
      id, created_at, last_modified_at, hash, title, url, release_item_id
    ) values (1005, now(), now(), 5, 'Video', 'https://example.invalid', 101);
    insert into public.release_item_work (
      id, created_at, last_modified_at, hash, work, label_id, release_item_id
    ) values (1006, now(), now(), 6, 'Published By', 20, 101);
  "
}

validate_release_relation_identity_migration() {
  local container_name=$1
  local database_name=$2

  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'identity_sha256'
      and table_name in (
        'release_item_credited_artist',
        'release_item_format',
        'release_item_identifier',
        'release_item_image',
        'release_item_track',
        'release_item_video',
        'release_item_work'
      )
      and data_type = 'bytea'
      and is_nullable = 'YES'
  " "7"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint
    where conname like 'ck_release_item_%_identity_sha256_length'
      and not convalidated
  " "7"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_indexes
    where schemaname = 'public'
      and indexdef like '%identity_sha256%'
  " "0"
  assert_scalar "$container_name" "$database_name" "
    select string_agg(id::text, ',' order by id)
    from (
      select id from public.release_item_credited_artist
      union all select id from public.release_item_format
      union all select id from public.release_item_identifier
      union all select id from public.release_item_image
      union all select id from public.release_item_track
      union all select id from public.release_item_video
      union all select id from public.release_item_work
    ) relation_rows
  " "1001,1002,1003,1004,1005,1006,1007"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from (
      select identity_sha256 from public.release_item_credited_artist
      union all select identity_sha256 from public.release_item_format
      union all select identity_sha256 from public.release_item_identifier
      union all select identity_sha256 from public.release_item_image
      union all select identity_sha256 from public.release_item_track
      union all select identity_sha256 from public.release_item_video
      union all select identity_sha256 from public.release_item_work
    ) relation_rows
    where identity_sha256 is null
  " "7"
  expect_sql_failure "$container_name" "$database_name" "
    update public.release_item_track
    set identity_sha256 = decode(repeat('00', 31), 'hex')
    where id = 1004;
  "
  execute_sql "$container_name" "$database_name" "
    update public.release_item_track
    set identity_sha256 = decode(repeat('00', 32), 'hex')
    where id = 1004;
  "
  assert_scalar "$container_name" "$database_name" "
    select octet_length(identity_sha256)
    from public.release_item_track
    where id = 1004
  " "32"
}

validate_release_format_quantity_migration() {
  local container_name=$1
  local database_name=$2
  local oversized_quantity="1010487400000000000000000000000000000000000000000000"

  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'release_item_format'
      and column_name = 'quantity_text'
      and data_type = 'text'
      and is_nullable = 'YES'
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint
    where conrelid = 'public.release_item_format'::regclass
      and conname in (
        'ck_release_item_format_quantity_text_decimal',
        'ck_release_item_format_quantity_consistent'
      )
      and not convalidated
  " "2"
  assert_scalar "$container_name" "$database_name" "
    select quantity::text || ':' || coalesce(quantity_text, 'null')
    from public.release_item_format
    where id = 1002
  " "1:null"
  expect_sql_failure "$container_name" "$database_name" "
    update public.release_item_format
    set quantity_text = '01'
    where id = 1002;
  "
  expect_sql_failure "$container_name" "$database_name" "
    update public.release_item_format
    set identity_sha256 = decode(repeat('00', 32), 'hex'),
        quantity_text = null
    where id = 1002;
  "
  expect_sql_failure "$container_name" "$database_name" "
    update public.release_item_format
    set identity_sha256 = decode(repeat('00', 32), 'hex'),
        quantity_text = '2'
    where id = 1002;
  "
  expect_sql_failure "$container_name" "$database_name" "
    update public.release_item_format
    set identity_sha256 = decode(repeat('00', 32), 'hex'),
        quantity = null,
        quantity_text = '1'
    where id = 1002;
  "
  execute_sql "$container_name" "$database_name" "
    update public.release_item_format
    set identity_sha256 = decode(repeat('00', 32), 'hex'),
        quantity_text = '1'
    where id = 1002;
  "
  expect_sql_failure "$container_name" "$database_name" "
    update public.release_item_format
    set quantity = 1,
        quantity_text = '$oversized_quantity'
    where id = 1002;
  "
  execute_sql "$container_name" "$database_name" "
    update public.release_item_format
    set quantity = null,
        quantity_text = '$oversized_quantity'
    where id = 1002;
  "
  assert_scalar "$container_name" "$database_name" "
    select quantity_text
    from public.release_item_format
    where id = 1002
  " "$oversized_quantity"
  assert_scalar "$container_name" "$database_name" "show lock_timeout" "0"
}

validate_identity_migration_lock_timeout() {
  local container_name=$1
  local database_name=$2
  local application_name="open-discogs-model-lock-holder-$test_run"
  local holder_pid
  local lock_ready=false
  local migration_error

  docker exec --env "PGAPPNAME=$application_name" "$container_name" \
    psql --username postgres --dbname "$database_name" --no-psqlrc \
    --set ON_ERROR_STOP=1 \
    --command "
      begin;
      lock table public.release_item_credited_artist in access share mode;
      select pg_sleep(30);
      commit;
    " >/dev/null 2>&1 &
  holder_pid=$!

  for _ in {1..100}; do
    if [[ "$(docker exec "$container_name" \
      psql --username postgres --dbname "$database_name" \
      --no-psqlrc --no-align --tuples-only \
      --command "
        select count(*)
        from pg_locks lock_state
        join pg_stat_activity activity on activity.pid = lock_state.pid
        where activity.application_name = '$application_name'
          and lock_state.relation =
            'public.release_item_credited_artist'::regclass
          and lock_state.mode = 'AccessShareLock'
          and lock_state.granted;")" == "1" ]]; then
      lock_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$lock_ready" != true ]]; then
    printf 'Lock holder did not acquire the relation lock\n' >&2
    return 1
  fi

  if migration_error="$(docker exec --interactive "$container_name" \
    psql --username postgres --dbname "$database_name" \
    --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction \
    < "$repository_root/schema/migrations/V010__release_credited_artist_identity.sql" \
    2>&1 >/dev/null)"; then
    printf 'V010 unexpectedly waited through lock contention\n' >&2
    return 1
  fi
  if [[ "$migration_error" != *"canceling statement due to lock timeout"* ]]; then
    printf 'V010 failed for an unexpected reason: %s\n' "$migration_error" >&2
    return 1
  fi
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'release_item_credited_artist'
      and column_name = 'identity_sha256'
  " "0"

  execute_sql "$container_name" "$database_name" "
    select pg_terminate_backend(pid)
    from pg_stat_activity
    where application_name = '$application_name';
  "
  wait "$holder_pid" || true
}

validate_successful_migration() {
  local container_name=$1
  local database_name=$2

  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from public.discogs_import_run_dump
    where import_contract_revision = 1
  " "4"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'discogs_import_run_dump'
      and column_name = 'import_contract_revision'
      and is_nullable = 'NO'
      and column_default is null
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint
    where conrelid in (
      'public.discogs_import_run_dump'::regclass,
      'public.release_item'::regclass,
      'public.master'::regclass
    )
      and conname in (
        'ck_discogs_import_run_dump_import_contract_revision_positive',
        'uq_release_item_master_id_id',
        'uq_master_main_release_id',
        'fk_master_id_main_release_id_release_item_master_id_id'
      )
      and convalidated
  " "4"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint
    where conrelid = 'public.master'::regclass
      and conname = 'fk_master_main_release_id_release_item'
  " "0"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'ix_release_item_master_id_id'
  " "0"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint constraint_definition
    join pg_index index_definition
      on index_definition.indexrelid = constraint_definition.conindid
    where constraint_definition.conrelid = 'public.release_item'::regclass
      and constraint_definition.conname = 'uq_release_item_master_id_id'
      and index_definition.indisunique
      and index_definition.indisvalid
      and pg_get_indexdef(index_definition.indexrelid)
        like '% USING btree (master_id, id)'
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_proc function_definition
    join pg_namespace function_schema
      on function_schema.oid = function_definition.pronamespace
    where function_schema.nspname = 'public'
      and function_definition.proname =
        'clear_stale_main_release_before_release_master_change'
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_trigger
    where tgrelid = 'public.release_item'::regclass
      and tgname = 'trg_release_item_clear_stale_main_release'
      and not tgisinternal
      and tgenabled = 'O'
  " "1"

  expect_sql_failure "$container_name" "$database_name" "
    with new_run as (
      insert into public.discogs_import_run (
        manifest_sha256, status, processor, processor_version
      ) values (repeat('b', 64), 'running', 'new-consumer', '2.0.0')
      returning id
    )
    insert into public.discogs_import_run_dump (
      import_run_id, entity_type, dump_id
    )
    select new_run.id, discogs_dump.entity_type, discogs_dump.id
    from new_run
    join public.discogs_dump on discogs_dump.entity_type = 'artist';
  "
  expect_sql_failure "$container_name" "$database_name" "
    with new_run as (
      insert into public.discogs_import_run (
        manifest_sha256, status, processor, processor_version
      ) values (repeat('c', 64), 'running', 'new-consumer', '2.0.0')
      returning id
    )
    insert into public.discogs_import_run_dump (
      import_run_id, entity_type, dump_id, import_contract_revision
    )
    select new_run.id, discogs_dump.entity_type, discogs_dump.id, 0
    from new_run
    join public.discogs_dump on discogs_dump.entity_type = 'artist';
  "
  expect_sql_failure "$container_name" "$database_name" "
    with new_run as (
      insert into public.discogs_import_run (
        manifest_sha256, status, processor, processor_version
      ) values (repeat('d', 64), 'running', 'new-consumer', '2.0.0')
      returning id
    )
    insert into public.discogs_import_run_dump (
      import_run_id, entity_type, dump_id, import_contract_revision
    )
    select new_run.id, discogs_dump.entity_type, discogs_dump.id, -1
    from new_run
    join public.discogs_dump on discogs_dump.entity_type = 'label';
  "
  execute_sql "$container_name" "$database_name" "
    with new_run as (
      insert into public.discogs_import_run (
        manifest_sha256, status, processor, processor_version
      ) values (repeat('e', 64), 'running', 'new-consumer', '2.0.0')
      returning id
    )
    insert into public.discogs_import_run_dump (
      import_run_id,
      entity_type,
      dump_id,
      import_contract_revision
    )
    select
      new_run.id,
      discogs_dump.entity_type,
      discogs_dump.id,
      case discogs_dump.entity_type
        when 'release' then 2
        else 1
      end
    from new_run
    cross join public.discogs_dump;
  "
  assert_scalar "$container_name" "$database_name" "
    select string_agg(
      run_dump.entity_type || ':' || run_dump.import_contract_revision,
      ',' order by run_dump.entity_type
    )
    from public.discogs_import_run_dump run_dump
    join public.discogs_import_run import_run
      on import_run.id = run_dump.import_run_id
    where import_run.manifest_sha256 = repeat('e', 64)
  " "artist:1,label:1,master:1,release:2"

  execute_sql "$container_name" "$database_name" \
    "update public.master set main_release_id = null where id = 2;"
  expect_sql_failure "$container_name" "$database_name" \
    "update public.master set main_release_id = 102 where id = 1;"

  execute_sql "$container_name" "$database_name" \
    "update public.master set main_release_id = 102 where id = 2;"
  execute_sql "$container_name" "$database_name" \
    "update public.release_item set master_id = 2 where id = 101;"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from public.master
    where id = 1
      and main_release_id is null
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select master_id
    from public.release_item
    where id = 101
  " "2"

  execute_sql "$container_name" "$database_name" \
    "update public.master set main_release_id = 101 where id = 2;"
  execute_sql "$container_name" "$database_name" \
    "update public.release_item set title = 'unrelated change' where id = 101;"
  assert_scalar "$container_name" "$database_name" \
    "select main_release_id from public.master where id = 2" "101"
  execute_sql "$container_name" "$database_name" "
    update public.release_item
    set master_id = master_id,
        title = 'unchanged master'
    where id = 101;
  "
  assert_scalar "$container_name" "$database_name" \
    "select main_release_id from public.master where id = 2" "101"
}

validate_failed_migration_rollback() {
  local container_name=$1
  local database_name=$2

  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'discogs_import_run_dump'
      and column_name = 'import_contract_revision'
  " "0"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint
    where conrelid = 'public.master'::regclass
      and conname = 'fk_master_main_release_id_release_item'
      and convalidated
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_constraint
    where conname in (
      'uq_release_item_master_id_id',
      'uq_master_main_release_id',
      'fk_master_id_main_release_id_release_item_master_id_id'
    )
      and conrelid in (
        'public.release_item'::regclass,
        'public.master'::regclass
      )
  " "0"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'ix_release_item_master_id_id'
  " "1"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_proc function_definition
    join pg_namespace function_schema
      on function_schema.oid = function_definition.pronamespace
    where function_schema.nspname = 'public'
      and function_definition.proname =
        'clear_stale_main_release_before_release_master_change'
  " "0"
  assert_scalar "$container_name" "$database_name" "
    select count(*)
    from pg_trigger
    where tgrelid = 'public.release_item'::regclass
      and tgname = 'trg_release_item_clear_stale_main_release'
      and not tgisinternal
  " "0"
}

run_postgres_contract_test() {
  local postgres_image=$1
  local postgres_major
  local container_name
  local volume_mounts
  local assert_tmpfs
  local heap_nodes_before
  local heap_nodes_after
  local database_name
  local tmpfs_path
  local pgdata_path="/var/lib/postgresql/data"

  postgres_major="${postgres_image#postgres:}"
  postgres_major="${postgres_major%%.*}"
  if (( postgres_major >= 18 )); then
    tmpfs_path="/var/lib/postgresql"
  else
    tmpfs_path="$pgdata_path"
  fi
  container_name="open-discogs-model-release-contract-pg${postgres_major}-$$"
  container_names+=("$container_name")

  docker run \
    --detach \
    --name "$container_name" \
    --label "io.dsub.test-owner=$test_owner" \
    --label "io.dsub.test-suite=$test_suite" \
    --label "io.dsub.test-run=$test_run" \
    --tmpfs "$tmpfs_path:rw,noexec,nosuid,size=512m" \
    --env "PGDATA=$pgdata_path" \
    --env POSTGRES_PASSWORD=contracttest \
    "$postgres_image" >/dev/null

  volume_mounts="$(docker container inspect \
    --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
    "$container_name")"
  if [[ -n "$volume_mounts" ]]; then
    while IFS= read -r volume_name; do
      if [[ -n "$volume_name" ]]; then
        created_volume_names+=("$volume_name")
      fi
    done <<< "$volume_mounts"
    printf 'Test container created a Docker volume: %s\n' "$volume_mounts" >&2
    return 1
  fi
  assert_tmpfs="$(docker container inspect \
    --format "{{index .HostConfig.Tmpfs \"$tmpfs_path\"}}" "$container_name")"
  if [[ "$assert_tmpfs" != *"size=512m"* \
    && "$assert_tmpfs" != *"size=536870912"* ]]; then
    printf 'PostgreSQL tmpfs size is not 512 MiB: %s\n' "$assert_tmpfs" >&2
    return 1
  fi
  if [[ "$assert_tmpfs" != *"noexec"* \
      || "$assert_tmpfs" != *"nosuid"* ]]; then
    printf 'PostgreSQL data directory is not the required tmpfs: %s\n' \
      "$assert_tmpfs" >&2
    return 1
  fi

  wait_for_postgres "$container_name"

  for database_name in \
    contract_good contract_bad_mismatch contract_bad_duplicate contract_lock; do
    execute_sql "$container_name" postgres "create database $database_name;"
    apply_migrations_through_v008 "$container_name" "$database_name"
    seed_import_run "$container_name" "$database_name"
  done

  seed_valid_release_relationships "$container_name" contract_good
  apply_v009 "$container_name" contract_good
  validate_successful_migration "$container_name" contract_good
  heap_nodes_before="$(relation_heap_nodes "$container_name" contract_good)"
  apply_release_identity_migrations "$container_name" contract_good
  heap_nodes_after="$(relation_heap_nodes "$container_name" contract_good)"
  if [[ "$heap_nodes_after" != "$heap_nodes_before" ]]; then
    printf 'Release relation heap rewrite detected: before=%s after=%s\n' \
      "$heap_nodes_before" "$heap_nodes_after" >&2
    return 1
  fi
  validate_release_relation_identity_migration "$container_name" contract_good
  validate_release_format_quantity_migration "$container_name" contract_good

  apply_v009 "$container_name" contract_lock
  validate_identity_migration_lock_timeout "$container_name" contract_lock

  execute_sql "$container_name" contract_bad_mismatch "
    insert into public.master (id, created_at, last_modified_at)
    values (1, now(), now()), (2, now(), now());
    insert into public.release_item (
      id, created_at, last_modified_at, master_id
    ) values (101, now(), now(), 2);
    update public.master set main_release_id = 101 where id = 1;
  "
  if apply_v009 "$container_name" contract_bad_mismatch 2>/dev/null; then
    printf 'V009 accepted an existing cross-master main release\n' >&2
    return 1
  fi
  validate_failed_migration_rollback "$container_name" contract_bad_mismatch
  assert_scalar "$container_name" contract_bad_mismatch "
    select count(*)
    from public.master master_item
    join public.release_item release_item
      on release_item.id = master_item.main_release_id
    where master_item.id = 1
      and release_item.id = 101
      and release_item.master_id = 2
  " "1"

  execute_sql "$container_name" contract_bad_duplicate "
    insert into public.master (id, created_at, last_modified_at)
    values (1, now(), now()), (2, now(), now());
    insert into public.release_item (
      id, created_at, last_modified_at, master_id
    ) values (101, now(), now(), 1);
    update public.master set main_release_id = 101 where id in (1, 2);
  "
  if apply_v009 "$container_name" contract_bad_duplicate 2>/dev/null; then
    printf 'V009 accepted duplicate existing main release ownership\n' >&2
    return 1
  fi
  validate_failed_migration_rollback "$container_name" contract_bad_duplicate
  assert_scalar "$container_name" contract_bad_duplicate "
    select count(*)
    from public.master
    where main_release_id = 101
  " "2"

  printf 'PostgreSQL %s release convergence contract passed\n' "$postgres_major"
}

for postgres_image in "${postgres_images[@]}"; do
  run_postgres_contract_test "$postgres_image"
done

printf 'Release convergence contract assertions passed\n'
