#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container_name="open-discogs-model-api-index-benchmark-$$"
postgres_image="postgres:18.4-alpine"
release_rows="${BENCH_RELEASE_ROWS:-1000000}"
artist_rows="${BENCH_ARTIST_ROWS:-250000}"
label_rows="${BENCH_LABEL_ROWS:-100000}"
master_rows="${BENCH_MASTER_ROWS:-250000}"
warmup_runs="${BENCH_WARMUP_RUNS:-5}"
measured_runs="${BENCH_MEASURED_RUNS:-30}"

require_positive_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be a positive integer: %s\n' "$name" "$value" >&2
    exit 1
  fi
}

require_positive_integer BENCH_RELEASE_ROWS "$release_rows"
require_positive_integer BENCH_ARTIST_ROWS "$artist_rows"
require_positive_integer BENCH_LABEL_ROWS "$label_rows"
require_positive_integer BENCH_MASTER_ROWS "$master_rows"
require_positive_integer BENCH_WARMUP_RUNS "$warmup_runs"
require_positive_integer BENCH_MEASURED_RUNS "$measured_runs"

cleanup() {
  case "$container_name" in
    open-discogs-model-api-index-benchmark-[0-9]*) ;;
    *)
      printf 'Refusing to clean unexpected container name: %s\n' "$container_name" >&2
      return 1
      ;;
  esac
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  if docker ps -a --filter "name=^/${container_name}$" --format '{{.Names}}' | grep -q .; then
    printf 'Benchmark container cleanup failed: %s\n' "$container_name" >&2
    return 1
  fi
}
trap cleanup EXIT INT TERM

docker run \
  --detach \
  --name "$container_name" \
  --label io.dsub.test-owner=open-discogs-model \
  --tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=4g \
  --env POSTGRES_DB=modelbench \
  --env POSTGRES_PASSWORD=modelbench \
  --env POSTGRES_USER=modelbench \
  "$postgres_image" >/dev/null

volume_mounts="$(
  docker inspect \
    --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
    "$container_name"
)"
if [[ -n "$volume_mounts" ]]; then
  printf 'Benchmark unexpectedly created Docker volumes: %s\n' "$volume_mounts" >&2
  exit 1
fi

for attempt in {1..30}; do
  if docker exec "$container_name" \
    psql --username modelbench --dbname modelbench --tuples-only \
      --command 'select 1' >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 30 ]]; then
    printf 'PostgreSQL did not become ready.\n' >&2
    exit 1
  fi
  sleep 1
done

psql_command() {
  docker exec "$container_name" \
    psql --username modelbench --dbname modelbench \
      --no-psqlrc --no-align --tuples-only --quiet \
      --set ON_ERROR_STOP=1 --command "$1"
}

for migration in "$repository_root"/schema/migrations/V00[1-6]__*.sql; do
  docker exec --interactive "$container_name" \
    psql --username modelbench --dbname modelbench \
      --no-psqlrc --quiet --set ON_ERROR_STOP=1 < "$migration"
done

psql_command "
  set synchronous_commit = off;
  insert into artist (id, created_at, last_modified_at, name, real_name)
  select id, timestamp '2026-08-11', timestamp '2026-08-11',
         'Artist ' || id, 'Real Artist ' || id
  from generate_series(1, $artist_rows) as id;

  insert into label (id, created_at, last_modified_at, name)
  select id, timestamp '2026-08-11', timestamp '2026-08-11', 'Label ' || id
  from generate_series(1, $label_rows) as id;

  insert into master (id, created_at, last_modified_at, title, year)
  select id, timestamp '2026-08-11', timestamp '2026-08-11',
         'Master ' || id, (1950 + id % 76)::smallint
  from generate_series(1, $master_rows) as id;

  insert into release_item (
    id, created_at, last_modified_at, country, has_valid_day,
    has_valid_month, has_valid_year, is_master, master_id,
    listed_release_date, release_date, title
  )
  select id, timestamp '2026-08-11', timestamp '2026-08-11',
         case id % 4 when 0 then 'US' when 1 then 'JP' when 2 then 'GB' else 'DE' end,
         true, true, true, id % 2 = 0,
         1 + id % $master_rows,
         to_char(make_date(1950 + id % 76, 1 + id % 12, 1 + id % 28), 'YYYY-MM-DD'),
         make_date(1950 + id % 76, 1 + id % 12, 1 + id % 28),
         case when id >= $release_rows - 2
              then 'Rare needle release ' || id
              else 'Catalog release ' || id end
  from generate_series(1, $release_rows) as id;

  insert into release_item_artist (
    id, created_at, last_modified_at, artist_id, release_item_id
  )
  select id, timestamp '2026-08-11', timestamp '2026-08-11',
         1 + id % $artist_rows, id
  from generate_series(1, $release_rows) as id;
  analyze;
"

query_duration() {
  local query="$1"
  local plan
  plan="$(psql_command "set jit = off; explain (analyze, format json) $query")"
  jq -r '.[0]["Execution Time"]' <<<"$plan"
}

query_plan() {
  local query="$1"
  local plan
  plan="$(psql_command "set jit = off; explain (analyze, buffers, format json) $query")"
  jq -c '.[0].Plan' <<<"$plan"
}

benchmark_query() {
  local phase="$1"
  local name="$2"
  local query="$3"
  local durations=()
  local iteration

  for ((iteration = 0; iteration < warmup_runs; iteration++)); do
    query_duration "$query" >/dev/null
  done
  for ((iteration = 0; iteration < measured_runs; iteration++)); do
    durations+=("$(query_duration "$query")")
  done

  printf '%s\n' "${durations[@]}" | sort -n | awk \
    -v phase="$phase" -v name="$name" '
      { values[NR] = $1 }
      END {
        p50 = int((NR - 1) * 0.50) + 1
        p95 = int((NR - 1) * 0.95) + 1
        p99 = int((NR - 1) * 0.99) + 1
        printf "%s\t%s\t%.3f\t%.3f\t%.3f\n",
          phase, name, values[p50], values[p95], values[p99]
      }
    '
}

deep_offset_query="select id from release_item order by id limit 30 offset $((release_rows - 100))"
keyset_query="select id from release_item where id > $((release_rows - 100)) order by id limit 31"
exact_count_query="select count(*) from release_item"
title_query="select id from release_item where title ilike '%rare needle%' and id > 0 order by id limit 31"
relationship_query="select release_item_id from release_item_artist where artist_id = $((artist_rows - 1)) and release_item_id > 0 order by release_item_id limit 31"

printf 'phase\tquery\tp50_ms\tp95_ms\tp99_ms\n'
benchmark_query before deep_offset "$deep_offset_query"
benchmark_query before exact_count "$exact_count_query"
benchmark_query before keyset "$keyset_query"
benchmark_query before title_contains "$title_query"
benchmark_query before artist_releases "$relationship_query"

printf 'plan_before\ttitle_contains\t%s\n' "$(query_plan "$title_query")"
printf 'plan_before\tartist_releases\t%s\n' "$(query_plan "$relationship_query")"
printf 'size_before_bytes\t%s\n' "$(psql_command "select pg_database_size(current_database())")"

docker exec --interactive "$container_name" \
  psql --username modelbench --dbname modelbench \
    --no-psqlrc --quiet --set ON_ERROR_STOP=1 \
    < "$repository_root/schema/migrations/V007__api_query_indexes.sql"
psql_command 'analyze;'

benchmark_query after keyset "$keyset_query"
benchmark_query after title_contains "$title_query"
benchmark_query after artist_releases "$relationship_query"
printf 'plan_after\ttitle_contains\t%s\n' "$(query_plan "$title_query")"
printf 'plan_after\tartist_releases\t%s\n' "$(query_plan "$relationship_query")"
printf 'size_after_bytes\t%s\n' "$(psql_command "select pg_database_size(current_database())")"
